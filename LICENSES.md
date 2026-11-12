# VAULTFALL - Licences

The source code and documents of this repository are released under the MIT licence (`LICENSE`).
This file lists the third-party components that the repository contains or that the project is built with, and the
terms they come with.

## 1. Godot Engine 4.7.2 (MIT)

VAULTFALL is built with Godot Engine (https://godotengine.org). The engine is not part of this repository; when you build
the game, the licence texts of the engine and of its bundled third-party components come with the Godot distribution
and its export templates. (`tools/dump_godot_licenses.gd` dumps them from a running engine.)

```
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 2. GUT - Godot Unit Test 9.7.0 (MIT)

The test framework in `game/addons/gut/` is GUT by Tom "Butch" Wesley (https://github.com/bitwes/Gut),
included unchanged with its own licence file `game/addons/gut/LICENSE.md`.

```
Copyright (c) 2018 Tom "Butch" Wesley
```

## 3. Fonts (SIL Open Font License 1.1)

The fonts in `game/assets/fonts/` come with their licence texts next to the font files.

| Font | Use | Copyright | Licence file |
|---|---|---|---|
| **Atkinson Hyperlegible Next** | text and numbers | (c) 2020-2024 The Atkinson Hyperlegible Next Project Authors (Braille Institute) | `game/assets/fonts/OFL-AtkinsonHyperlegibleNext.txt` |
| **Departure Mono** 1.500 | titles | (c) 2022-2024 Helena Zhang | `game/assets/fonts/OFL-DepartureMono.txt` |
| **Vaultfall Symbols** (a modified subset of Noto Sans Symbols 2) | symbols | (c) 2022 The Noto Project Authors | `game/assets/fonts/OFL-VaultfallSymbols.txt` |

`tools/make_symbol_font.py` builds Vaultfall Symbols from the original Noto Sans Symbols 2, whose licence text is in
`tools/fontsrc/OFL-NotoSansSymbols2.txt` (the original font file is not included: download it from Google Fonts).
The fonts are not sold on their own, and the modified one carries a different name, as the licence requires.

## 4. Optional Steam integration

`game/src/platform/` contains optional code that can talk to Steam through GodotSteam (MIT) when it is present.
Neither GodotSteam nor the Steamworks SDK is part of this repository, and the game runs fully offline without them.

## 5. Python tools

The scripts in `tools/` use the Python standard library and Pillow (HPND licence), which are installed from PyPI
and are not distributed here.

## 6. What the MIT licence of this repository does not cover

The art, the audio and the game data of VAULTFALL are not in this repository and are not licensed by it.
