# PROGRESS - public snapshot

This file replaces the internal development log, which is not published. It records the state of this snapshot only.

## State of the project

- Game version: see `game/version.json` (1.0.0 in the private development tree). All the systems described in
  `docs/` are implemented there: skills and crafting, class-based combat, crates, estate, prestige layers, eras and
  trials, seasonal events, optional LAN/VPN co-op, optional Steam integration, Italian and English texts.
- Roadmap: the milestone plan in `docs/22_roadmap.md` is the original plan; it is historical, not a promise.

## What this snapshot is

- A single initial commit with the source code, tools and design documents. No development history.
- No art, no audio, no generated game data (see `README.md`).
- Not runnable as a complete game without your own data; see "Placeholders and your own data" in `README.md`.

## What can be verified here

| Check | Command | Needs data/Godot |
|---|---|---|
| Formulas against reference values | `python tests/test_framework_standalone.py` | no |
| GDScript sanity (brackets, strings, indentation) | `python tools/gd_lint.py game` | no |
| GUT tests | `python tools/run_tests.py` | Godot 4.7.2; almost all also need data |

## Open items

- Decide whether and when to publish the content modules (`tools/gamedata/`) so that the whole data pipeline runs in public.
- Confirm in a Godot run which GUT tests pass without data (the list in `README.md` comes from reading the code).
