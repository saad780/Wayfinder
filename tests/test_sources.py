"""Meaningful acceptance checks for replacement provenance and coverage."""
import copy
import importlib.util
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


builder = module("build_seed")
exporter = module("export_observations")


class SourcesTest(unittest.TestCase):
    def setUp(self):
        self.old = next(r for r in builder.baseline() if r["cat"] == "mailbox")
        self.record = {**self.old, "verified": True, "source": "own", "accuracy": 4,
                       "rect": {"width": 3600, "height": 2400}}
        self.document = {"schema": 1, "sources": {"own": {"origin": "wayfinder", "build": "70170",
                         "description": "Independent interaction", "license": "client-observation"}},
                         "records": [self.record]}

    def test_empty_and_unreviewed_inputs_keep_entire_baseline(self):
        self.record["verified"] = False
        _, report = builder.build_dataset(self.document, "70170")
        self.assertEqual(report["baselineEntries"], 763)
        self.assertEqual(report["remainingEntries"], 763)
        self.assertEqual(report["remainingByCategory"]["transport"], 28)
        self.assertEqual(sum(report["remainingByZone"].values()), 763)
        self.assertEqual(report["independentEntries"], 0)

    def test_verified_measurement_replaces_only_matching_coverage(self):
        self.record["x"] += .1
        lua, report = builder.build_dataset(self.document, "70170")
        self.assertGreaterEqual(report["replacedEntries"], 1)
        self.assertEqual(report["remainingEntries"] + report["replacedEntries"], 763)
        self.assertEqual(report["remainingByCategory"]["flight"], 64)
        L = LuaRuntime()
        ns = L.table()
        L.execute(lua, "Wayfinder", ns)
        e = ns.IndependentSeedData[1]
        self.assertIn(builder.key(self.old), list(e.replaces.values()))
        self.assertEqual(e.source, "own")
        self.assertEqual(e.pts[1], self.record["mapID"])
        self.assertEqual(builder.build_dataset(self.document, "70170")[0], lua)

    def test_unknown_copyleft_and_missing_permission_are_rejected(self):
        for source in ({"origin": "addon", "description": "copied"},
                       {"origin": "external", "description": "public repository", "license": "GPL-3.0", "url": "https://example.org", "dataPermission": "GPL"},
                       {"origin": "external", "description": "public page", "license": "MIT", "url": "https://example.org"}):
            with self.subTest(source=source):
                self.document["sources"]["own"] = source
                with self.assertRaises(ValueError):
                    builder.build_dataset(self.document, "70170")

    def test_invalid_build_precision_and_coordinates_are_rejected(self):
        with self.assertRaises(ValueError):
            builder.build_dataset(self.document, "different")
        for field, value in (("x", float("nan")), ("y", 101), ("accuracy", 28), ("faction", 1.5), ("mapID", True)):
            doc = copy.deepcopy(self.document)
            doc["records"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                builder.build_dataset(doc, "70170")

    def test_class_faction_profession_and_destination_are_not_interchangeable(self):
        for cat, field, change in (("trainer_class", "class", "OTHER"), ("bank", "faction", 99),
                                   ("trainer_prof", "label", "Different profession"), ("transport", "label", "Different destination")):
            old = next(r for r in builder.baseline() if r["cat"] == cat)
            new = {**old, "rect": self.record["rect"], field: change}
            self.assertFalse(builder.compatible(old, new))

    def test_export_only_new_measurements_and_keep_them_unverified(self):
        saved = '''WayfinderDB = { pois = { old = { cats = { bank = true } } }, observations = {
          own = { build = "70170", version = "1.60.1", method = "talk", name = "Measured Banker",
            mapID = 1429, x = 40, y = 60, accuracy = 4, faction = 1, cat = "bank",
            rect = { cont = 0, top = -8000, left = 1600, width = 3600, height = 2400 } } } }'''
        data = exporter.export(saved)
        self.assertEqual(len(data["records"]), 1)
        self.assertFalse(data["records"][0]["verified"])
        self.assertEqual(data["records"][0]["label"], "Measured Banker")
        self.assertEqual(exporter.export('WayfinderDB = { pois = { old = {} } }')["records"], [])
        with self.assertRaises(Exception):
            exporter.export('os.execute("bad")')

    def test_permissive_data_notices_and_utf8_survive_generation(self):
        self.document["sources"]["own"] = {"origin": "external", "description": "Independent survey", "license": "MIT",
                                             "url": "https://example.org/data", "dataPermission": "https://example.org/LICENSE",
                                             "notice": "Copyright survey authors\nMIT license text supplied by source"}
        self.record["label"] = 'Boîte "aux lettres"'
        generated, _ = builder.build_dataset(self.document, "70170")
        self.assertIn("-- Copyright survey authors", generated)
        lua = LuaRuntime()
        ns = lua.table()
        lua.execute(generated, "Wayfinder", ns)
        self.assertEqual(ns.IndependentSeedData[1].name, self.record["label"])


if __name__ == "__main__":
    unittest.main()
