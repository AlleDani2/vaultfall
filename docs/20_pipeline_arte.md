# 20 - Art and asset pipeline (public summary)

The game's pixel-art images are produced outside this repository and are **not published here**. This page explains
how the code expects images to arrive, so that you can supply your own.

## What the code expects

- Every image is referenced by a `res://assets/...` path inside the game data (field `icon`, `portrait`, `banner`, ...).
- Native sizes per path prefix are in `assets_plan/asset_specs.json` (for example 32x32 for item icons). Images are
  authored at that size and are only ever scaled up by an integer factor with nearest-neighbour filtering in Godot.
- **Rule D-6 - colour operations only:** generated PNGs may be recoloured or palette-remapped, never resized, cropped
  or otherwise changed in geometry. Prefer palette shaders in Godot over editing files.

## Placeholders

`python tools/make_placeholders.py` creates a simple placeholder image for every image path found in the data, at the
native size from `asset_specs.json`. Existing files are not overwritten unless you pass `--force`. This makes the game
playable before any real art exists.

## Bringing your own art

1. Put your images under `game/assets/<category>/` using the same file names the data refers to (the placeholder
   generator shows you the list).
2. Keep the native sizes from `assets_plan/asset_specs.json`.
3. Let Godot import them (open the project once, or run `godot --headless --path game --import`).

## Audio

The sound set is synthesised by `tools/make_audio.py` from `assets_plan/audio_manifest.csv`; no third-party samples
are involved. `tests/test_audio_levels.py` measures the rendered files because audio cannot be judged by ear in CI.
