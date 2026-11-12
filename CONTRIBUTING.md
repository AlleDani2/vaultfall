# Contributing to VAULTFALL

Thank you for your interest. This is a small project with strict rules; reading this page first will save you time.

## What you can work on

This repository has the code, the tools and the design documents, but **not the game data, art or audio**
(see the README). Good contributions therefore are:

- bug fixes and refactors in `game/src/` (systems, UI, save/load, co-op, platform code);
- tests: GUT tests in `game/tests/`, Python tests in `tests/`;
- tooling in `tools/` (test runner, linters, generators that do not need the private content);
- documentation fixes and translations of the design documents;
- UI strings in `localization/parts/*.csv` (Italian and English).

If your change needs the game data to be verified, say so in the pull request; the maintainers will check it on their side.

## Ground rules (from `CLAUDE.md`)

1. **Generated data is never edited by hand.** Change the generator modules, not the JSON they produce.
2. **No balance numbers in GDScript.** Read them from `data/constants.json` (via `DataRegistry`); formulas are ported
   1:1 from `tools/gamedata/core.py` and verified with `tests/reference_values.json`.
3. **Logic apart from UI.** Systems are pure `RefCounted` classes in `game/src/systems/`, deterministic, tested with GUT.
   No `await` in systems. The UI listens to `EventBus` and calls systems.
4. **One modifier system**: every bonus goes through `Modifiers.gd` using the add/more rule.
5. **Crates stay ethical and legal** (`docs/09`, `docs/24`): only in-game currency and keys, never real money, no trading,
   no stake modes, visible probabilities, result drawn before the animation, filler items with real probabilities.
   Pull requests that weaken these rules will be declined.
6. **Bilingual text**: Italian and English everywhere; use `tr()` and `localization/ui_strings.csv`, never a hard-coded
   visible string.
7. **Saves are sacred**: atomic writes, backups, versioned schema with migrations. Never break an existing save without a migration.
8. **Original names only**: do not add names, art or text from other games or brands.
9. **PNG files: colour operations only** (recolouring, palette remapping); never resize or crop generated images.

## GDScript conventions

Typed GDScript; files and classes in `PascalCase`, functions and variables in `snake_case`, constants in `UPPER_SNAKE`;
`class_name` for systems; UI refreshed at 10 Hz at most; long lists virtualised. Details: `docs/17_architettura_godot.md` section 12.

## How to submit a change

1. Open an issue for anything larger than a small fix, so we can agree on the approach.
2. Fork, create a branch, keep commits small and descriptive.
3. Before opening the pull request run what you can:
   - `python tests/test_framework_standalone.py`
   - `python tools/gd_lint.py game`
   - `python tools/run_tests.py --select <your test file>` if you have Godot 4.7.2 and the data.
4. In the pull request, say what you ran and what you could not run.

By contributing you agree that your contribution is licensed under the project's [MIT licence](LICENSE).

## Conduct

Be kind and be specific. Disagree with ideas, not people.
