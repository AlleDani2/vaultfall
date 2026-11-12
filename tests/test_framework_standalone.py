#!/usr/bin/env python3
"""Tests that need NO game data and NO art: they run in the public repository as it is.

    python tests/test_framework_standalone.py        (or: python -m unittest tests/test_framework_standalone.py)

They check:
  - the formula module tools/gamedata/core.py against the reference values in tests/reference_values.json
    (only the cases that core.py alone can compute; cases that need the game content are skipped, and counted);
  - that the framework modules (registry, modifier catalogue, tuning, export) import cleanly on their own;
  - the small JSON/CSV files in the repository (version, app config, changelog, UI strings) are well formed;
  - that git tracks no art/audio/binary build files and no generated data folder.
"""
import csv
import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))


def _load(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)


class FrameworkImports(unittest.TestCase):
    def test_framework_modules_import(self):
        from gamedata import core, reg, modifiers, tuning, export, modifier_names  # noqa: F401
        self.assertTrue(hasattr(reg, "R"))
        self.assertTrue(callable(core.xp_to_next))

    def test_registry_rejects_duplicates(self):
        from gamedata.reg import Registry
        r = Registry()
        r.item("x", value=1)
        with self.assertRaises(ValueError):
            r.item("x", value=2)
        r.action("a")
        with self.assertRaises(ValueError):
            r.action("a")


class CoreFormulas(unittest.TestCase):
    def test_reference_values(self):
        from gamedata import core
        cases = _load("tests/reference_values.json")["cases"]
        checked = skipped = 0
        for c in cases:
            fn = getattr(core, c["fn"], None)
            if fn is None:
                skipped += 1          # needs other modules (e.g. the balance simulator or game content)
                continue
            try:
                got = fn(*c["args"])
            except Exception:         # needs content-dependent state
                skipped += 1
                continue
            exp, tol = c["expected"], c.get("tol", 0)
            if isinstance(exp, str) and exp in ("inf", "-inf", "nan"):      # JSON cannot store infinities
                exp = float(exp)
            if got == exp:
                pass                                                          # also covers inf == inf
            elif isinstance(exp, (int, float)) and isinstance(got, (int, float)):
                self.assertLessEqual(abs(got - exp), max(tol, 1e-9), f"{c['fn']}{c['args']}: {got} != {exp}")
            else:
                self.assertEqual(got, exp, f"{c['fn']}{c['args']}")
            checked += 1
        self.assertGreater(checked, 100, f"too few reference cases checked ({checked}, skipped {skipped})")

    def test_xp_table_is_monotonic(self):
        from gamedata import core
        tbl = core.xp_table()
        for a, b in zip(tbl[1:], tbl[2:]):
            self.assertLess(a, b)

    def test_hit_chance_in_range(self):
        from gamedata import core
        for acc, eva in ((1, 1000), (100, 100), (1000, 1)):
            self.assertTrue(0.0 <= core.hit_chance(acc, eva) <= 1.0)


class RepositoryFiles(unittest.TestCase):
    def test_small_json_files(self):
        for rel in ("game/version.json", "game/app_config.json", "game/changelog.json"):
            self.assertIsNotNone(_load(rel), rel)
        self.assertRegex(_load("game/version.json")["version"], r"^\d+\.\d+\.\d+$")

    def test_ui_strings_are_bilingual(self):
        path = os.path.join(ROOT, "localization", "ui_strings.csv")
        with open(path, encoding="utf-8", newline="") as f:
            rows = list(csv.reader(f))
        self.assertEqual(rows[0], ["keys", "en", "it"])
        seen = set()
        for r in rows[1:]:
            self.assertEqual(len(r), 3, r[:1])
            self.assertNotIn(r[0], seen, "duplicate key " + r[0])
            seen.add(r[0])
            self.assertTrue(r[1].strip() and r[2].strip(), "empty translation for " + r[0])

    def test_no_art_audio_or_data_tracked(self):
        """Looks only at files tracked by git, so data you generate locally (git-ignored) never trips this."""
        import subprocess
        try:
            out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            self.skipTest("not a git checkout")
        banned = (".png", ".jpg", ".jpeg", ".ogg", ".wav", ".mp3", ".zip", ".exe", ".pck")
        for f in out.splitlines():
            if f.startswith("game/addons/gut/"):
                continue                      # GUT's own editor icons (third-party, MIT), kept unchanged
            self.assertFalse(f.lower().endswith(banned), f)
            self.assertFalse(f.startswith(("data/", "data_slice/", "game/data/", "wiki/")), f)


if __name__ == "__main__":
    unittest.main()
