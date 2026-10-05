"""Build reviewed independent seeds and report retained legacy coverage.

python tools/build_seed.py data/observations.json [--check]
Requires lupa to read the bundled baseline; candidate inputs are inert JSON.
"""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
PERMISSIVE = {"CC0-1.0", "MIT", "BSD-2-Clause", "BSD-3-Clause", "ISC", "CC-BY-4.0"}
CLASSES = {"DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"}
KINDS = {"boat", "zeppelin", "tram", "portal"}
CATEGORIES = {"trainer_prof", "trainer_class", "auction", "bank", "mailbox", "flight", "inn", "transport"}


def quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + '"'


def number(r, field, low=None, high=None):
    v = r.get(field)
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
        raise ValueError(f"{field} must be finite")
    if (low is not None and v < low) or (high is not None and v > high):
        raise ValueError(f"{field} outside permitted range")
    return v


def key(r):
    return f"s:{r['cat']}:{r['mapID']}:{r['x']:.1f}:{r['y']:.1f}"


def baseline():
    lua = LuaRuntime()
    ns = lua.table()
    for filename in ("Seed.lua", "Transports.lua"):
        lua.execute((ROOT / "Wayfinder/Data" / filename).read_text(encoding="utf-8"), "Wayfinder", ns)
    out = []
    for _, e in ns.SeedData.items():
        for i in range(1, len(e.pts) + 1, 4):
            out.append(dict(cat=e.cat, label=e.name, **{"class": e['class']}, mapID=int(e.pts[i]),
                            x=e.pts[i + 1], y=e.pts[i + 2], faction=int(e.pts[i + 3])))
    for _, t in ns.TransportData.items():
        out.append(dict(cat="transport", kind=t[1], mapID=int(t[2]), x=t[3], y=t[4], label=t[5], faction=int(t[6])))
    return out


def validate(r, sources, build):
    source = sources.get(r.get("source"))
    if not isinstance(source, dict) or not isinstance(source.get("description"), str) or not source["description"]:
        raise ValueError("reviewed record needs source description")
    if source.get("origin") in {"client", "wayfinder"}:
        if source.get("build") != build or source.get("license") != "client-observation":
            raise ValueError("client observations need the target build and client-observation designation")
    elif source.get("origin") == "external":
        if source.get("license") not in PERMISSIVE or not source.get("url") or not source.get("dataPermission"):
            raise ValueError("external data needs permissive data terms, URL, and permission reference")
        if source["license"] != "CC0-1.0" and (not isinstance(source.get("notice"), str) or not source["notice"].strip()):
            raise ValueError("external sources with notice requirements need their license/attribution text")
    else:
        raise ValueError("unknown or addon-derived source")
    if r.get("cat") not in CATEGORIES:
        raise ValueError("unsupported seed category")
    if number(r, "mapID", 1) != int(r["mapID"]):
        raise ValueError("mapID must be an integer")
    number(r, "x", 0, 100)
    number(r, "y", 0, 100)
    number(r, "accuracy", 0, 8)
    if number(r, "faction", 0, 2) not in (0, 1, 2):
        raise ValueError("invalid faction")
    if not isinstance(r.get("label"), str) or not r["label"] or any(ord(c) < 32 for c in r["label"]):
        raise ValueError("label must be nonempty and have no control characters")
    number(r.get("rect", {}), "width", 1)
    number(r.get("rect", {}), "height", 1)
    if r["cat"] == "trainer_class" and r.get("class") not in CLASSES:
        raise ValueError("class trainer needs a class token")
    if r["cat"] == "transport" and r.get("kind") not in KINDS:
        raise ValueError("transport needs a supported kind")


def distance(a, b):
    return math.hypot((a["x"] - b["x"]) * b["rect"]["width"] / 100,
                      (a["y"] - b["y"]) * b["rect"]["height"] / 100)


def compatible(old, new):
    if (old["cat"], old["mapID"], old["faction"], old.get("class"), old.get("kind")) != (new["cat"], new["mapID"], new["faction"], new.get("class"), new.get("kind")):
        return False
    if old["cat"] in {"transport", "trainer_prof"} and old["label"] != new["label"]:
        return False
    return distance(old, new) <= 25


def build_dataset(document, build):
    if not isinstance(document, dict) or document.get("schema") != 1:
        raise ValueError("unsupported manifest schema")
    sources = document.get("sources", {})
    if not isinstance(sources, dict) or not isinstance(document.get("records", []), list):
        raise ValueError("sources must be an object and records a list")
    reviewed = []
    for r in document.get("records", []):
        if not isinstance(r, dict):
            raise ValueError("record must be an object")
        if r.get("verified") is True:
            validate(r, sources, build)
            reviewed.append(r)
    reviewed.sort(key=lambda r: (r["accuracy"], key(r), r["source"], r["label"]))
    unique = []
    for r in reviewed:
        neighbors = [u for u in unique if u["cat"] == r["cat"] and u["mapID"] == r["mapID"] and distance(u, r) <= 8]
        if neighbors:
            if not all(compatible(u, r) for u in neighbors):
                raise ValueError("conflicting same-category replacements within eight yards")
            continue
        unique.append(r)
    unique.sort(key=lambda r: (key(r), r["source"], r["label"]))
    legacy = baseline()
    aliases, remaining = {}, []
    for old in legacy:
        matches = sorted((r for r in unique if compatible(old, r)), key=lambda r: distance(old, r))
        if matches and (len(matches) == 1 or distance(old, matches[0]) < distance(old, matches[1]) - 1e-6):
            aliases.setdefault(key(matches[0]), []).append(key(old))
        else:
            remaining.append(old)
    lines = ["-- GENERATED by tools/build_seed.py from reviewed independent measurements.",
             f"-- Target client build: {build}. See the generation manifest and coverage report."]
    for source_id in sorted({r["source"] for r in unique}):
        source = sources[source_id]
        lines.append("-- Source: " + json.dumps({"id": source_id, **source}, ensure_ascii=False, sort_keys=True))
        for notice in source.get("notice", "").splitlines():
            lines.append("-- " + notice)
    lines.append("local _, ns = ...")
    for transport, table in ((False, "IndependentSeedData"), (True, "IndependentTransportData")):
        lines.append(f"ns.{table} = {{")
        for r in unique:
            if (r["cat"] == "transport") != transport:
                continue
            tail = ", accuracy = %g, source = %s, replaces = { %s }" % (r["accuracy"], quote(r["source"]), ",".join(quote(k) for k in sorted(set(aliases.get(key(r), [])))))
            if transport:
                head = "%s,%d,%.8f,%.8f,%s,%d" % (quote(r["kind"]), r["mapID"], r["x"], r["y"], quote(r["label"]), r["faction"])
            else:
                head = "cat = %s, name = %s, pts = { %d,%.8f,%.8f,%d }" % (quote(r["cat"]), quote(r["label"]), r["mapID"], r["x"], r["y"], r["faction"])
                if r.get("class"):
                    head += ", class = " + quote(r["class"])
            lines.append("  { " + head + tail + " },")
        lines.append("}")
    report = dict(schema=1, build=build, baselineEntries=len(legacy), independentEntries=len(unique),
                  replacedEntries=len(legacy) - len(remaining), remainingEntries=len(remaining),
                  unreviewedRecords=sum(r.get("verified") is not True for r in document.get("records", [])),
                  remainingByCategory=dict(sorted(Counter(r["cat"] for r in remaining).items())),
                  remainingByZone=dict(sorted(Counter(str(r["mapID"]) for r in remaining).items())),
                  remainingByFaction=dict(sorted(Counter(str(r["faction"]) for r in remaining).items())),
                  remainingByClass=dict(sorted(Counter(r["class"] for r in remaining if r.get("class")).items())),
                  remainingByProfession=dict(sorted(Counter(r["label"] for r in remaining if r["cat"] == "trainer_prof").items())),
                  remainingRoutes=[r for r in remaining if r["cat"] == "transport"],
                  remaining=remaining, sources=sources,
                  licenseStatus="GPL retained: legacy imports remain" if remaining else "Provenance review required before relicensing")
    return "\n".join(lines) + "\n", report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--build", default="70170")
    parser.add_argument("--output", type=Path, default=ROOT / "Wayfinder/Data/Independent.lua")
    parser.add_argument("--report", type=Path, default=ROOT / "data/coverage.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        lua, report = build_dataset(json.loads(args.manifest.read_text(encoding="utf-8")), args.build)
    except (ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    if not args.check:
        args.output.write_text(lua, encoding="utf-8")
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{report['independentEntries']} independent entries; {report['replacedEntries']} replaced; {report['remainingEntries']} legacy entries retained")


if __name__ == "__main__":
    main()
