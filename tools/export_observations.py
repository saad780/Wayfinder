"""Export new observations for review, never merged legacy POIs. Requires lupa.

python tools/export_observations.py <SavedVariables/Wayfinder.lua> candidate.json
Exported records start unverified and cannot remove built-in markers.
"""
import argparse
import json
from pathlib import Path
from lupa.lua51 import LuaRuntime


def export(saved_variables):
    lua = LuaRuntime(register_eval=False, register_builtins=False)
    load = lua.eval("function(text) local env = {}; local f = assert(loadstring(text)); setfenv(f, env); f(); return env end")
    env = load(saved_variables)
    db = env.WayfinderDB
    out = {"schema": 1, "sources": {}, "records": []}
    if not db or not db.observations:
        return out
    for _, o in sorted(db.observations.items()):
        source = f"wayfinder:{o.build}:{o.method}"
        out["sources"][source] = {"origin": "wayfinder", "build": o.build, "license": "client-observation",
                                   "description": f"Wayfinder {o.method} observations from client {o.version} build {o.build}"}
        r = {field: o[field] for field in ("mapID", "x", "y", "accuracy", "cat", "class", "faction", "npcID", "nodeID", "kind", "observedAt", "title") if o[field] is not None}
        r.update(source=source, verified=False, label=o.name or o.cat, rect={k: v for k, v in o.rect.items()})
        out["records"].append(r)
    out["records"].sort(key=lambda r: (r["cat"], r["mapID"], r["x"], r["y"], r["source"]))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("saved_variables", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    document = export(args.saved_variables.read_text(encoding="utf-8-sig"))
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{len(document['records'])} observations exported for review")


if __name__ == "__main__":
    main()
