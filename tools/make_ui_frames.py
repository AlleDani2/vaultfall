#!/usr/bin/env python3
"""Genera i telai UI originali di VAULTFALL (9-slice, controlli, logo, stati vuoti) in game/assets/ui/frames/.

Disegno procedurale e DETERMINISTICO con Pillow: nessun download, nessun antialiasing (ogni pixel ha alpha 0 o 255),
nessuna casualita'. Sono immagini NUOVE (non toccano i PNG d'arte, regola 10 di CLAUDE.md).
Scrive anche frames.json (dimensioni, margini 9-slice) letto da game/scripts/build_theme.gd.

Uso:  python tools/make_ui_frames.py [--check]
  --check   non scrive: verifica che i file su disco coincidano con quelli generati e siano a pixel esatti.
Dopo la rigenerazione:  godot --headless --path game --import  e poi  godot --headless --path game -s res://scripts/build_theme.gd
Palette: neutri "caveau" (blu-grigio scuro) + ottone; accenti di sezione (oliva / ruggine / oro / viola-azzurro);
rarita' dai colori del progetto (data/crate_rules.json: rare, epic, legendary, mythic, relic) + comune grigio.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "ui" / "frames"


# ---------------------------------------------------------------- colori
def hx(s: str) -> tuple:
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def mix(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def ramp(base: str) -> dict:
    """Rampa a 6 toni da un colore base: k (quasi nero), o (contorno), d (scuro), m (medio), l (base), h (luce)."""
    c = hx(base)
    return {"k": mix(c, BLACK, 0.86), "o": mix(c, BLACK, 0.72), "d": mix(c, BLACK, 0.5), "m": mix(c, BLACK, 0.25),
            "l": c, "h": mix(c, WHITE, 0.45)}


STEEL = ramp("#5b6378")          # bordi neutri del caveau
BRASS = ramp("#c9a45c")          # ottone (accento di default = Citta')
OLIVE = ramp("#8fa84a")          # Mansioni
RUST = ramp("#c4603a")           # Avventura
INDIGO = ramp("#7d8cf0")         # Progresso (viola/azzurro)
ACCENTS = {"city": BRASS, "skills": OLIVE, "adventure": RUST, "progress": INDIGO}
RARITIES = {"common": ramp("#8a8f99"), "rare": ramp("#8DA2B8"), "epic": ramp("#6F7BE6"),
            "legendary": ramp("#C65AA8"), "mythic": ramp("#E8702A"), "relic": ramp("#F5CF4F")}

PANEL = hx("#1b1e26")
PANEL2 = hx("#232733")
RAISED = hx("#2a2f3d")
INSET = hx("#0f1115")
OUTLINE = hx("#07080b")

MANIFEST: dict = {}
IMAGES: dict = {}


# ---------------------------------------------------------------- primitive
def new(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), CLEAR)


def depth(x: int, y: int, w: int, h: int, cut: int) -> int:
    """Profondita' del pixel dal bordo esterno della forma smussata (-1 = fuori)."""
    cx = min(x, w - 1 - x)
    cy = min(y, h - 1 - y)
    d = min(cx, cy)
    while d >= 0 and (cx - d) + (cy - d) < max(cut - d, 0):
        d -= 1
    return d


def box(w: int, h: int, rings: list, fill, cut: int = 2) -> Image.Image:
    """Rettangolo smussato con anelli concentrici. Un anello puo' essere [colore_alto_sx, colore_basso_dx]."""
    im = new(w, h)
    n = len(rings)
    for y in range(h):
        for x in range(w):
            d = depth(x, y, w, h, cut)
            if d < 0:
                continue
            if d < n:
                r = rings[d]
                if isinstance(r, list):
                    tl = min(x, y) <= min(w - 1 - x, h - 1 - y)
                    c = r[0] if tl else r[1]
                else:
                    c = r
            else:
                c = fill(x, y) if callable(fill) else fill
            im.putpixel((x, y), c)
    return im


def vgrad(top: tuple, bot: tuple, y0: int, y1: int):
    def f(x: int, y: int) -> tuple:
        t = 0.0 if y1 <= y0 else min(max((y - y0) / (y1 - y0), 0.0), 1.0)
        return mix(top, bot, t)
    return f


def dither(a: tuple, b: tuple):
    return lambda x, y: a if (x + y) % 2 == 0 else b


def stamp(im: Image.Image, rows: list, lg: dict, ox: int, oy: int, mirror: bool = True) -> None:
    """Disegna un motivo ASCII sull'angolo alto-sinistra e lo specchia sugli altri tre."""
    w, h = im.size
    corners = [(1, 1), (-1, 1), (1, -1), (-1, -1)] if mirror else [(1, 1)]
    for sx, sy in corners:
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                if ch == ".":
                    continue
                x = ox + c if sx > 0 else w - 1 - (ox + c)
                y = oy + r if sy > 0 else h - 1 - (oy + r)
                if 0 <= x < w and 0 <= y < h:
                    im.putpixel((x, y), CLEAR if ch == "x" else lg[ch])


def legend(r: dict) -> dict:
    return {"o": r["o"], "d": r["d"], "m": r["m"], "l": r["l"], "h": r["h"], "k": r["k"], "a": mix(r["h"], WHITE, 0.4),
            "b": r["l"], "s": OUTLINE}


RIVET = ["..oo..", ".ohlo.", "ohlmdo", "olmddo", ".odoo.", "..oo.."]
RIVET_S = [".oo.", "ohmo", "omdo", ".oo."]
DOT = [".h.", "hlh", ".h."]
DIAMOND = ["..h..", ".hlm.", "hlalm", ".hlm.", "..m.."]
GEM = ["...s...", "..sas..", ".sabbs.", "sabhbbs", ".sbbbs.", "..sbs..", "...s..."]
FLAME = ["..h.....", "..hl....", ".hll..m.", ".hlll.mm", "hllhlmmd", "hlhhlmd.", ".hlhmmd.", "..hmdd.."]
STAR = ["...h...", "...h...", "..hlh..", "hhhlhhh", ".hlllh.", "..hlh..", ".hh.hh.", "hh...hh"]
BRACKET = ["oooooooo", "ohhhhhho", "ohalllmo", "ohlmoooo", "ohlmo...", "ohlmo...", "ohlmo...", "ooooo..."]
BRACKET_S = ["oooooo", "ohhhho", "ohalmo", "ohlooo", "ohmo..", "oooo.."]
SPIKE = ["h.......", "hl......", "hlm.....", "hlmd....", "hl......", "h......."]
VINE = [".llllll.", "lmmmmmml", "lm.....l", "lm.lll..", "lm.lmml.", "l..lm.m.", ".l.l..l.", "...l..l."]


def reg(name: str, im: Image.Image, margin: tuple | None = None, **extra) -> None:
    IMAGES[name] = im
    d = {"size": [im.width, im.height]}
    if margin is not None:
        d["margin"] = list(margin)
    d.update(extra)
    MANIFEST[name] = d


# ---------------------------------------------------------------- pannelli
def panel_img(kind: str, acc: dict, trim: dict = STEEL) -> tuple:
    """Restituisce (immagine, margine) per base / raised / inset / card / window / tooltip / log."""
    if kind == "base":
        rings = [OUTLINE, trim["m"] if acc is BRASS else acc["d"], trim["d"], mix(PANEL, BLACK, 0.3)]
        im = box(32, 32, rings, PANEL, 3)
        stamp(im, BRACKET, legend(acc), 0, 0)
        return im, 10
    if kind == "content":
        rings = [OUTLINE, trim["m"] if acc is BRASS else acc["d"], trim["d"], mix(INSET, BLACK, 0.2)]
        im = box(32, 32, rings, hx("#121419"), 3)
        stamp(im, BRACKET, legend(acc), 0, 0)
        return im, 10
    if kind == "raised":
        rings = [OUTLINE, [trim["l"], trim["d"]], [mix(RAISED, WHITE, 0.14), mix(RAISED, BLACK, 0.4)],
                 [mix(RAISED, WHITE, 0.06), mix(RAISED, BLACK, 0.25)]]
        im = box(32, 32, rings, vgrad(mix(RAISED, WHITE, 0.03), RAISED, 4, 28), 3)
        stamp(im, BRACKET, legend(acc), 0, 0)
        return im, 10
    if kind == "inset":
        rings = [OUTLINE, [mix(INSET, BLACK, 0.5), trim["d"]], mix(INSET, BLACK, 0.2)]
        return box(24, 24, rings, dither(INSET, mix(INSET, WHITE, 0.025)), 2), 8
    if kind == "card":
        rings = [OUTLINE, acc["d"] if acc is not BRASS else trim["m"], mix(PANEL2, WHITE, 0.05)]
        im = box(24, 24, rings, vgrad(mix(PANEL2, WHITE, 0.02), PANEL, 3, 20), 3)
        stamp(im, BRACKET_S, legend(acc), 0, 0)
        return im, 8
    if kind == "window":
        rings = [OUTLINE, acc["d"], acc["l"], acc["m"], OUTLINE, mix(PANEL, BLACK, 0.35), mix(PANEL, BLACK, 0.15)]
        im = box(48, 48, rings, PANEL, 5)
        stamp(im, VINE, legend(acc), 1, 1)
        stamp(im, RIVET, legend(acc), 7, 7)
        return im, 16
    if kind == "tooltip":
        rings = [OUTLINE, acc["m"], mix(PANEL, BLACK, 0.2)]
        im = box(16, 16, rings, mix(PANEL, BLACK, 0.12), 2)
        stamp(im, ["h.", ".."], legend(acc), 1, 1)
        return im, 6
    if kind == "log":
        rings = [OUTLINE, [mix(PANEL, BLACK, 0.4), trim["d"]], mix(PANEL, BLACK, 0.25)]
        im = box(24, 24, rings, mix(PANEL, BLACK, 0.12), 1)
        stamp(im, ["mm", "m."], legend(trim), 1, 1)
        return im, 8
    raise ValueError(kind)


def banner_title(acc: dict, h: int = 28, w: int = 64) -> tuple:
    """Placca del titolo di schermata: estremita' smussate con rombo, filetti sopra e sotto."""
    im = new(w, h)
    top = vgrad(mix(acc["d"], PANEL, 0.55), mix(PANEL, BLACK, 0.2), 0, h - 1)
    for y in range(h):
        for x in range(w):
            im.putpixel((x, y), top(x, y))
    for x in range(w):
        for y, c in ((0, OUTLINE), (1, acc["m"]), (2, acc["d"]), (h - 1, OUTLINE), (h - 2, acc["m"]), (h - 3, acc["d"])):
            im.putpixel((x, y), c)
    for y in range(3, h - 3):
        for x, c in ((0, OUTLINE), (1, acc["m"])):
            im.putpixel((x, y), c)
            im.putpixel((w - 1 - x, y), c)
    for (x, y) in ((0, 0), (1, 0), (0, 1), (0, h - 1), (1, h - 1), (0, h - 2)):
        im.putpixel((x, y), CLEAR)
        im.putpixel((w - 1 - x, y), CLEAR)
    lg = legend(acc)
    oy = (h - 7) // 2
    for r, row in enumerate(GEM):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((5 + c, oy + r), lg[ch])
                im.putpixel((w - 1 - (5 + c), oy + r), lg[ch])
    for x in range(13, 21):
        im.putpixel((x, h // 2), acc["m"])
        im.putpixel((w - 1 - x, h // 2), acc["m"])
    return im, (22, 4, 22, 4)


def banner_section(acc: dict) -> tuple:
    """Fascetta piccola per i titoli di sezione del menu: filetto con rombo a sinistra."""
    w, h = 40, 16
    im = new(w, h)
    for y in range(1, h - 1):
        for x in range(w):
            im.putpixel((x, y), mix(PANEL2, PANEL, y / (h - 1)))
    for x in range(w):
        im.putpixel((x, h - 1), acc["d"])
        im.putpixel((x, h - 2), acc["m"])
    for r, row in enumerate(GEM):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((3 + c, 3 + r), legend(acc)[ch])
    return im, (12, 2, 6, 2)


def topbar(acc: dict) -> tuple:
    w, h = 16, 32
    im = new(w, h)
    for y in range(24):
        for x in range(w):
            im.putpixel((x, y), mix(RAISED, PANEL, y / 24))
    strip = [acc["m"], acc["l"], acc["m"], OUTLINE, mix(PANEL, BLACK, 0.25), mix(PANEL, BLACK, 0.45), OUTLINE, OUTLINE]
    for i, c in enumerate(strip):
        for x in range(w):
            im.putpixel((x, 24 + i), c)
    for r, row in enumerate(RIVET_S):          # borchia ogni 16 px nella fascia
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((6 + c, 26 + r), legend(acc)[ch])
    return im, (0, 0, 0, 8)


def sidebar() -> tuple:
    w, h = 24, 16
    im = new(w, h)
    base = mix(PANEL, BLACK, 0.18)
    for y in range(h):
        for x in range(16):
            im.putpixel((x, y), base if (x + y) % 2 == 0 else mix(base, WHITE, 0.02))
    for x, c in zip(range(16, 24), [STEEL["d"], STEEL["m"], STEEL["d"], OUTLINE, OUTLINE, OUTLINE, OUTLINE, OUTLINE]):
        for y in range(h):
            im.putpixel((x, y), c)
    for y in (3, 4, 11, 12):                 # tacche di rilievo sul bordo
        im.putpixel((17, y), BRASS["m"])
    return im, (0, 0, 8, 0)


def background_tile() -> Image.Image:
    """Mattonella 32x32 senza giunte: reticolo di rombi molto tenue + puntini."""
    n = 32
    im = Image.new("RGBA", (n, n), hx("#101217"))
    line, dot = hx("#141720"), hx("#191d29")
    for i in range(n):
        im.putpixel((i, i), line)
        im.putpixel((i, (n - i) % n), line)
    for (x, y) in ((0, 0), (16, 16), (16, 0), (0, 16)):
        im.putpixel((x, y), dot)
        im.putpixel(((x + 1) % n, y), dot)
        im.putpixel((x, (y + 1) % n), dot)
    return im


# ---------------------------------------------------------------- pulsanti
def button(state: str, kind: str) -> tuple:
    """24x24 margine 7. kind: 'std' (acciaio) | 'accent' (ottone). state: normal/hover/pressed/disabled."""
    base, edge = (hx("#4d3f22"), BRASS) if kind == "accent" else (hx("#2d3240"), STEEL)
    ft, fb = mix(base, WHITE, 0.10), mix(base, BLACK, 0.12)
    if state == "hover":
        ft, fb = mix(ft, WHITE, 0.10), mix(fb, WHITE, 0.07)
        hi, lo = edge["h"], edge["d"]
    elif state == "pressed":
        ft, fb = mix(base, BLACK, 0.30), mix(base, BLACK, 0.18)
        hi, lo = edge["d"], edge["l"]
    elif state == "disabled":
        gray = hx("#262830")
        ft, fb = mix(gray, WHITE, 0.03), mix(gray, BLACK, 0.1)
        hi = lo = hx("#3a3d46")
    else:
        hi, lo = edge["l"], edge["d"]
    rings = [OUTLINE, [hi, lo], [mix(hi, ft, 0.6), mix(lo, fb, 0.5)]]
    im = box(24, 24, rings, vgrad(ft, fb, 3, 20), 2)
    return im, 7


def focus_ring() -> tuple:
    """Anello di focus ben visibile (tastiera/gamepad): filetto chiaro con contorno scuro e squadre agli angoli."""
    w = 24
    im = new(w, w)
    c1 = hx("#f3e3b0")
    for x in range(w):
        for y in range(w):
            d = depth(x, y, w, w, 1)
            if d == 0:
                im.putpixel((x, y), OUTLINE)
            elif d == 1:
                im.putpixel((x, y), c1)
    stamp(im, ["hh", "h."], {"h": hx("#ffffff")}, 1, 1)
    return im, 7


def sidebar_button(state: str) -> tuple:
    w = 24
    im = new(w, w)
    if state == "pressed":                       # voce selezionata: placca con barra ottone
        for y in range(w):
            for x in range(w):
                if y in (0, w - 1):
                    im.putpixel((x, y), OUTLINE)
                elif y in (1, w - 2):
                    im.putpixel((x, y), BRASS["d"])
                else:
                    im.putpixel((x, y), mix(hx("#3a3220"), hx("#272a35"), x / (w - 1)))
        for y in range(0, w):
            for x, c in ((0, OUTLINE), (1, BRASS["h"]), (2, BRASS["l"]), (3, BRASS["m"])):
                im.putpixel((x, y), c)
    else:                                        # hover
        for y in range(1, w - 1):
            for x in range(w):
                im.putpixel((x, y), mix(hx("#232733"), hx("#1b1e26"), x / (w - 1)))
            im.putpixel((0, y), BRASS["d"])
            im.putpixel((1, y), BRASS["m"])
    return im, 7


# ---------------------------------------------------------------- campi, tab, barre
def line_edit(kind: str) -> tuple:
    if kind == "focus":
        rings = [OUTLINE, BRASS["l"], BRASS["d"]]
    elif kind == "readonly":
        rings = [OUTLINE, STEEL["d"], mix(INSET, BLACK, 0.2)]
    else:
        rings = [OUTLINE, [STEEL["d"], STEEL["m"]], mix(INSET, BLACK, 0.3)]
    return box(24, 24, rings, INSET if kind != "readonly" else mix(INSET, PANEL, 0.4), 2), 8


def search_field(focus: bool) -> tuple:
    """Campo di ricerca: la lente e' nel bordo sinistro (cappuccio da 26 px)."""
    w, h, cap = 44, 24, 26
    rings = [OUTLINE, BRASS["l"] if focus else [STEEL["d"], STEEL["m"]], BRASS["d"] if focus else mix(INSET, BLACK, 0.3)]
    im = box(w, h, rings, INSET, 2)
    lens = [".oooo.", "o.hh.o", "oh...o", "oh...o", "o....o", ".oooo.", ".....oo", "......oo"]
    col = {"o": STEEL["h"] if not focus else BRASS["h"], "h": WHITE}
    for r, row in enumerate(lens):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((8 + c, 6 + r), col[ch])
    return im, (cap, 8, 8, 8)


def tab(kind: str) -> tuple:
    """24x24, margini (7,7,7,3): angoli alti smussati, base aperta per la selezionata."""
    w = 24
    im = new(w, w)
    edge = STEEL
    if kind == "selected":
        ft, fb, edge = mix(RAISED, WHITE, 0.06), PANEL, BRASS
    elif kind == "hover":
        ft, fb = mix(PANEL2, WHITE, 0.06), PANEL2
    elif kind == "disabled":
        ft = fb = mix(PANEL, BLACK, 0.2)
        edge = ramp("#3a3d46")
    else:
        ft, fb = mix(PANEL, BLACK, 0.1), mix(PANEL, BLACK, 0.25)
    for y in range(w):
        for x in range(w):
            cx = min(x, w - 1 - x)
            if y < 2 and cx < 3 - y:
                continue
            if y == 0:
                c = OUTLINE
            elif y == 1:
                c = edge["l"] if kind in ("selected", "hover") else edge["m"]
            elif cx == 0:
                c = OUTLINE
            elif cx == 1:
                c = edge["d"] if kind == "selected" else edge["m"]
            else:
                c = ft if y < 14 else fb
                if kind != "selected" and y >= w - 2:
                    c = OUTLINE if y == w - 1 else mix(fb, BLACK, 0.2)
            im.putpixel((x, y), c)
    return im, (7, 7, 7, 3)


def progress_bg() -> tuple:
    rings = [OUTLINE, [mix(INSET, BLACK, 0.4), STEEL["m"]], mix(INSET, BLACK, 0.25)]
    return box(16, 16, rings, vgrad(mix(INSET, BLACK, 0.2), mix(INSET, WHITE, 0.03), 3, 12), 2), 4


def progress_fill(acc: dict) -> tuple:
    """Riempimento 16x16 margine 2; chiaro in alto, scuro in basso, riga di luce e segmenti leggeri."""
    w = 16
    im = new(w, w)
    for y in range(w):
        c = mix(acc["h"], acc["d"], min(1.0, y / (w - 1) * 1.25))
        if y == 0:
            c = mix(acc["h"], WHITE, 0.25)
        elif y == w - 1:
            c = acc["o"]
        elif y == w - 2:
            c = acc["d"]
        for x in range(w):
            im.putpixel((x, y), c)
    for y in range(1, w - 1):
        im.putpixel((w - 1, y), mix(acc["l"], WHITE, 0.2))
    return im, 2


def slider_track(fill: bool, acc: dict = BRASS) -> tuple:
    if fill:
        return box(16, 8, [OUTLINE, acc["h"], acc["m"]], acc["l"], 1), (4, 3, 4, 3)
    rings = [OUTLINE, [mix(INSET, BLACK, 0.4), STEEL["m"]], mix(INSET, BLACK, 0.2)]
    return box(16, 8, rings, INSET, 1), (4, 3, 4, 3)


def grabber(kind: str) -> Image.Image:
    rows = ["....oooooo....", "...ohhhhhho...", "..ohlllllllo..", ".ohllhhhhllmo.", "ohllhllllhlmdo", "ohlllllllllmdo",
            "ohlllhhhllmmdo", "ohlllllllmmddo", ".ohmmmmmmmddo.", "..odddddddoo..", "...oooooooo..."]
    rr = {"normal": BRASS, "highlight": ramp("#e6c47a"), "disabled": ramp("#5d5f66")}[kind]
    im = new(16, 16)
    lg = {k: rr[k] for k in "ohlmd"}
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((1 + c, 2 + r), lg[ch])
    return im


def scroll_img(kind: str) -> tuple:
    """12x12, margine 4. kind: track / grab / hover / pressed."""
    if kind == "track":
        return box(12, 12, [OUTLINE, [mix(INSET, BLACK, 0.4), STEEL["d"]]], mix(INSET, BLACK, 0.1), 2), 4
    base = {"grab": STEEL, "hover": ramp("#8a93ab"), "pressed": BRASS}[kind]
    rings = [OUTLINE, [base["h"], base["d"]], [base["l"], base["m"]]]
    return box(12, 12, rings, vgrad(base["l"], base["m"], 3, 9), 2), 4


def separator_h() -> tuple:
    w, h = 48, 9
    im = new(w, h)
    for x in range(w):
        im.putpixel((x, 3), STEEL["d"])
        im.putpixel((x, 4), STEEL["m"])
        im.putpixel((x, 5), OUTLINE)
    lg = legend(BRASS)
    for r, row in enumerate(GEM):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((2 + c, 1 + r), lg[ch])
                im.putpixel((w - 1 - (2 + c), 1 + r), lg[ch])
    for x in range(10, 14):
        im.putpixel((x, 4), BRASS["m"])
        im.putpixel((w - 1 - x, 4), BRASS["m"])
    return im, (14, 0, 14, 0)


# ---------------------------------------------------------------- icone dei controlli
def check_icon(checked: bool, disabled: bool = False, radio: bool = False) -> Image.Image:
    im = new(16, 16)
    edge = STEEL if not disabled else ramp("#4a4c53")
    col = BRASS if not disabled else ramp("#6a6b72")
    if radio:
        rows = ["....oooooo....", "..ooddddddoo..", ".oddddddddddo.", ".oddddddddddo.", "oddddddddddddo",
                "oddddddddddddo", "oddddddddddddo", "oddddddddddddo", ".oddddddddddo.", ".oddddddddddo.",
                "..ooddddddoo..", "....oooooo...."]
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                if ch == "o":
                    im.putpixel((1 + c, 2 + r), edge["m"] if r > 1 else edge["l"])
                elif ch == "d":
                    im.putpixel((1 + c, 2 + r), INSET)
        if checked:
            for r, row in enumerate(["..hh..", ".hlll.", "hlllmd", "hlllmd", ".lmmd.", "..dd.."]):
                for c, ch in enumerate(row):
                    if ch != ".":
                        im.putpixel((5 + c, 5 + r), col[ch])
        return im
    for y in range(1, 15):
        for x in range(1, 15):
            m = min(x - 1, y - 1, 14 - x, 14 - y)
            if m == 0:
                if x in (1, 14) and y in (1, 14):
                    continue
                im.putpixel((x, y), OUTLINE)
            elif m == 1:
                im.putpixel((x, y), edge["m"] if x + y < 15 else edge["d"])
            else:
                im.putpixel((x, y), INSET)
    if checked:
        for (x, y) in [(4, 8), (5, 9), (6, 10), (7, 9), (8, 8), (9, 7), (10, 6), (11, 5)]:
            im.putpixel((x, y), col["l"])
            im.putpixel((x, y + 1), col["m"])
            if x >= 6:
                im.putpixel((x, y - 1), col["h"])
    return im


def switch_icon(on: bool, disabled: bool = False) -> Image.Image:
    w, h = 32, 16
    track = BRASS if on else STEEL
    if disabled:
        track = ramp("#4a4c53")
    rings = [OUTLINE, [track["d"], track["m"]], mix(track["d"], BLACK, 0.2) if on else mix(INSET, BLACK, 0.2)]
    im = box(w, h, rings, mix(track["m"], BLACK, 0.45) if on else INSET, 4)
    kx = w - 13 if on else 3
    kn = (BRASS if on else ramp("#8a93ab")) if not disabled else ramp("#5d5f66")
    lg = {"o": OUTLINE, "h": kn["h"], "l": kn["l"], "m": kn["m"], "d": kn["d"]}
    rows = ["..oooooo..", ".ohhhhhhm.", "ohhlllllmd", "ohllllllmd", "ohllllllmd", "ohlllllmmd", ".ohmmmmmd.", "..oooooo.."]
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((kx + c, 4 + r - 1 + 0), lg[ch])
    return im


def arrow_down() -> Image.Image:
    im = new(12, 12)
    for r, row in enumerate(["hhhhhhh", ".hlllm.", "..hlm..", "...m..."]):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((2 + c, 4 + r), BRASS[ch])
    return im


def arrow_small(direction: str) -> Image.Image:
    base = arrow_down()
    return {"down": base, "up": base.transpose(Image.FLIP_TOP_BOTTOM),
            "right": base.transpose(Image.ROTATE_90).transpose(Image.FLIP_LEFT_RIGHT),
            "left": base.transpose(Image.ROTATE_90)}[direction]


# ---------------------------------------------------------------- cornici di rarita'
def rarity_card(r: dict, tier: int) -> tuple:
    """32x32 margine 10; tier 0..5 = comune, rara, epica, leggendaria, mitica, reliquia."""
    if tier == 5:
        rings = [OUTLINE, r["h"], r["l"], r["d"], r["h"], mix(PANEL, r["d"], 0.3)]
    elif tier >= 3:
        rings = [OUTLINE, r["l"], r["d"], mix(PANEL, r["d"], 0.25)]
    else:
        rings = [OUTLINE, r["m"] if tier else r["d"], mix(PANEL, r["d"], 0.2)]
    fillc = mix(PANEL, r["d"], 0.12 + 0.04 * tier)
    im = box(32, 32, rings, vgrad(mix(fillc, WHITE, 0.03), mix(fillc, BLACK, 0.1), 4, 28), 3)
    lg = legend(r)
    motifs = {1: (BRACKET_S, 0, 0), 2: (BRACKET, 0, 0), 3: (BRACKET, 0, 0), 4: (FLAME, 0, 0), 5: (STAR, 0, 0)}
    if tier in motifs:
        mo, ox, oy = motifs[tier]
        stamp(im, mo, lg, ox, oy)
    if tier in (2, 3):
        stamp(im, DIAMOND, lg, 5, 5)                            # gemma dentro l'angolo (non sul bordo che si ripete)
    return im, 10


def rarity_slot(r: dict, tier: int) -> tuple:
    """24x24 margine 6: cornice sottile per le icone."""
    rings = [OUTLINE, r["m"] if tier else r["d"], r["d"] if tier else STEEL["k"]]
    if tier >= 4:
        rings = [OUTLINE, r["l"], r["m"], r["d"]]
    im = box(24, 24, rings, mix(INSET, r["d"], 0.15), 2)
    if tier >= 1:
        stamp(im, ["h.", ".."], legend(r), 0, 0)
    return im, 6


# ---------------------------------------------------------------- logo e illustrazioni
FONT5 = {
    "V": ["X...X", "X...X", "X...X", "X...X", ".X.X.", ".X.X.", "..X.."],
    "A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
    "U": ["X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
    "L": ["X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"],
    "T": ["XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."],
    "F": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."],
}


def logo() -> Image.Image:
    """Logo VAULTFALL: lettere a blocchi sbalzati in oro con ombra, arco del caveau sopra e schegge che cadono sotto."""
    s = 5
    word = "VAULTFALL"
    tw = len(word) * 5 * s + (len(word) - 1) * s
    W, H = tw + 52, 146
    im = new(W, H)
    x0, y0 = 26, 52
    gold = ramp("#f0b43a")
    cx = W // 2
    # arco del caveau: semi-ellisse a bande (contorno, ottone scuro, chiaro, medio, contorno) con giunti radiali e chiave di volta
    ax, by_ = W // 2 - 6, 38
    base_y = 44
    bands = [OUTLINE, BRASS["d"], BRASS["l"], BRASS["h"], BRASS["m"], OUTLINE]
    for i, col in enumerate(bands):
        a_i, b_i = ax - i * 3 // 2, by_ - i * 3 // 2
        for k in range(0, 4001):
            t = math.pi * k / 4000
            x = int(round(cx + a_i * math.cos(t)))
            y = int(round(base_y - b_i * math.sin(t)))
            if 0 <= x < W and 0 <= y < H:
                im.putpixel((x, y), col)
    for deg in range(15, 166, 15):                                # giunti tra i conci
        t = math.radians(deg)
        for i in range(1, len(bands) - 1):
            x = int(round(cx + (ax - i * 3 // 2) * math.cos(t)))
            y = int(round(base_y - (by_ - i * 3 // 2) * math.sin(t)))
            im.putpixel((x, y), BRASS["d"] if i != 3 else BRASS["m"])
    for yy in range(base_y - 6, base_y + 1):                      # piedritti
        for i, col in enumerate(bands):
            for sx in (-1, 1):
                for ex in (0, 1) if i else (0,):
                    im.putpixel((cx + sx * (ax - i * 3 // 2 + (ex if sx > 0 else -ex)), yy), col)
    for dy in range(0, 10):                                         # chiave di volta
        for dx in range(-5 + dy // 3, 6 - dy // 3):
            im.putpixel((cx + dx, 1 + dy), OUTLINE if (dy == 0 or abs(dx) == 5 - dy // 3) else (BRASS["h"] if dy < 4 else BRASS["l"]))
    # ombra, contorno e lettere a blocchi
    for pass_ in ("shadow", "outline", "fill"):
        px = x0
        for ch in word:
            for r, row in enumerate(FONT5[ch]):
                for c, v in enumerate(row):
                    if v != "X":
                        continue
                    bx, by = px + c * s, y0 + r * s
                    if pass_ == "shadow":
                        rng = (by + 3, by + s + 3, bx + 3, bx + s + 3)
                        col = mix(OUTLINE, BLACK, 0.4)
                    elif pass_ == "outline":
                        rng = (by - 1, by + s + 1, bx - 1, bx + s + 1)
                        col = OUTLINE
                    else:
                        rng = None
                    if rng:
                        for yy in range(rng[0], rng[1]):
                            for xx in range(rng[2], rng[3]):
                                im.putpixel((xx, yy), col)
                    else:
                        base = mix(mix(gold["l"], WHITE, 0.12), gold["d"], r / 6 * 0.85)
                        for yy in range(s):
                            for xx in range(s):
                                c2 = base
                                if yy == 0 or xx == 0:
                                    c2 = mix(base, WHITE, 0.35)
                                elif yy == s - 1 or xx == s - 1:
                                    c2 = mix(base, BLACK, 0.4)
                                im.putpixel((bx + xx, by + yy), c2)
            px += 6 * s
    # filetto con rombo e schegge che cadono sotto il nome
    ly = y0 + 7 * s + 8
    for x in range(30, W - 30):
        im.putpixel((x, ly), BRASS["m"])
        im.putpixel((x, ly + 1), OUTLINE)
    for r, row in enumerate(DIAMOND):
        for c, ch in enumerate(row):
            if ch != ".":
                im.putpixel((cx - 2 + c, ly - 2 + r), legend(BRASS)[ch])
    azure = ramp("#5fb0d6")
    shards = [(-70, 8, 2, INDIGO), (-46, 15, 3, azure), (-22, 6, 2, INDIGO), (24, 11, 3, azure),
              (48, 5, 2, INDIGO), (72, 14, 2, azure), (-92, 14, 2, azure), (94, 7, 2, INDIGO)]
    for dx, dy, sz, col in shards:
        sx, sy = cx + dx, ly + 8 + dy
        for k in range(-sz, sz + 1):
            for j in range(-(sz - abs(k)), sz - abs(k) + 1):
                c = col["h"] if (k + j) <= -sz else (col["l"] if j < 1 else col["m"])
                if 0 <= sx + k < W and 0 <= sy + j < H:
                    im.putpixel((sx + k, sy + j), c)
    return im


def vault_door() -> Image.Image:
    """Portello del caveau (160x160): anello d'acciaio con bulloni d'ottone, disco con anello, ruota a sei raggi e mozzo."""
    n = 160
    im = new(n, n)
    c = (n - 1) / 2
    bolts = [(c + 70 * math.cos(math.radians(a * 22.5)), c + 70 * math.sin(math.radians(a * 22.5))) for a in range(16)]
    spokes = [math.radians(a * 60 + 15) for a in range(6)]
    for y in range(n):
        for x in range(n):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy)
            if r > 79:
                continue
            col = None
            if r > 77:
                col = OUTLINE
            elif r > 62:                                    # anello esterno: acciaio con luce in alto a sinistra
                lit = (dx + dy) < 0
                col = STEEL["h"] if r > 75 and lit else STEEL["l"] if lit else STEEL["m"] if r > 70 else STEEL["d"]
                if r > 61.5 and r < 63:
                    col = OUTLINE
            elif r > 60:
                col = OUTLINE
            else:                                           # disco interno
                col = mix(STEEL["d"], STEEL["k"], r / 60)
                if (dx + dy) < 0 and r > 56:
                    col = mix(col, STEEL["m"], 0.5)
                if 47 < r < 50:
                    col = BRASS["m"] if (dx + dy) < 0 else BRASS["d"]
                elif 46 < r <= 47 or 50 <= r < 51:
                    col = OUTLINE
                for ang in spokes:                          # raggi: distanza dal segmento
                    ux, uy = math.cos(ang), math.sin(ang)
                    t = dx * ux + dy * uy
                    if 10 < t < 47:
                        d = abs(-dx * uy + dy * ux)
                        if d < 2.6:
                            col = BRASS["h"] if d < 1.0 else BRASS["l"] if d < 2.0 else OUTLINE
                if r < 15:
                    col = OUTLINE if r > 13.5 else (BRASS["h"] if (dx + dy) < -4 else BRASS["l"] if r > 8 else BRASS["m"])
                    if r < 6:
                        col = OUTLINE if r > 4.5 else STEEL["k"]
            im.putpixel((x, y), col)
    for bx, by in bolts:                                    # bulloni
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                rr = math.hypot(dx, dy)
                if rr < 3.2:
                    px, py = int(round(bx)) + dx, int(round(by)) + dy
                    im.putpixel((px, py), OUTLINE if rr > 2.3 else (BRASS["h"] if dx + dy < 0 else BRASS["m"]))
    return im


def _rect(im: Image.Image, x0: int, y0: int, x1: int, y1: int, c: tuple) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            im.putpixel((x, y), c)


def empty_chest() -> Image.Image:
    im = new(48, 40)
    wood, wl = ramp("#8b6a3e"), BRASS
    _rect(im, 8, 8, 39, 19, OUTLINE)                          # coperchio ribaltato indietro
    _rect(im, 9, 9, 38, 18, wood["d"])
    _rect(im, 9, 9, 38, 10, wood["m"])
    _rect(im, 12, 12, 35, 18, INSET)                           # interno vuoto
    for x in (13, 21, 29):
        im.putpixel((x, 14), mix(INSET, WHITE, 0.18))
    _rect(im, 6, 20, 41, 35, OUTLINE)                          # corpo
    _rect(im, 7, 21, 40, 34, wood["m"])
    _rect(im, 7, 21, 40, 22, wood["l"])
    _rect(im, 7, 33, 40, 34, wood["d"])
    for x in range(10, 40, 6):
        _rect(im, x, 24, x, 32, wood["d"])
    for x0 in (8, 36):                                          # fasce di ottone
        _rect(im, x0, 20, x0 + 3, 35, OUTLINE)
        _rect(im, x0 + 1, 21, x0 + 2, 34, wl["m"])
        _rect(im, x0 + 1, 21, x0 + 1, 34, wl["l"])
    _rect(im, 21, 24, 26, 30, OUTLINE)                         # serratura
    _rect(im, 22, 25, 25, 29, wl["l"])
    _rect(im, 23, 26, 24, 27, OUTLINE)
    _rect(im, 4, 36, 43, 37, mix(OUTLINE, BLACK, 0.2))
    return im


def empty_scroll() -> Image.Image:
    im = new(48, 40)
    pa = ramp("#d8c9a0")
    _rect(im, 10, 4, 37, 33, OUTLINE)
    _rect(im, 11, 5, 36, 32, mix(pa["m"], BLACK, 0.2))
    _rect(im, 11, 5, 36, 6, pa["l"])
    for y in range(9, 30, 4):                                  # righe vuote tratteggiate
        for x in range(15, 33, 4):
            _rect(im, x, y, x + 1, y, mix(pa["m"], BLACK, 0.45))
    for (y0, y1) in ((2, 6), (31, 35)):                        # rulli
        _rect(im, 7, y0, 40, y1, OUTLINE)
        _rect(im, 8, y0 + 1, 39, y1 - 1, BRASS["m"])
        _rect(im, 8, y0 + 1, 39, y0 + 1, BRASS["h"])
    return im


def empty_shelf() -> Image.Image:
    im = new(48, 40)
    wood = ramp("#7c5a36")
    for y0 in (14, 30):
        _rect(im, 3, y0, 44, y0 + 5, OUTLINE)
        _rect(im, 4, y0 + 1, 43, y0 + 4, wood["m"])
        _rect(im, 4, y0 + 1, 43, y0 + 1, wood["l"])
    for (x, y) in ((5, 6), (41, 6), (5, 22), (41, 22)):
        _rect(im, x, y, x + 1, y + 8, OUTLINE)
    for (x, y) in ((22, 12), (23, 12), (24, 12), (25, 12), (21, 13), (26, 13)):    # un'impronta di polvere
        im.putpixel((x, y), mix(INSET, WHITE, 0.2))
    return im


# ---------------------------------------------------------------- assemblaggio
def build() -> None:
    IMAGES.clear()
    MANIFEST.clear()
    for kind in ("base", "raised", "inset", "card", "window", "tooltip", "log", "content"):
        im, m = panel_img(kind, BRASS)
        reg("panel_" + kind, im, (m,) * 4, **({"tile": "xy"} if kind == "inset" else {}))
        for sec, acc in ACCENTS.items():
            if sec == "city" or kind in ("raised", "inset", "tooltip", "log"):
                continue
            im, m = panel_img(kind, acc)
            reg("panel_%s_%s" % (kind, sec), im, (m,) * 4)
    for sec, acc in ACCENTS.items():
        im, mg = banner_title(acc)
        reg("banner_title_" + sec, im, mg)
        im, mg = banner_section(acc)
        reg("banner_section_" + sec, im, mg)
        im, mg = topbar(acc)
        reg("topbar_" + sec, im, mg, tile="x")
    im, mg = sidebar()
    reg("sidebar", im, mg, tile="xy")
    reg("bg_tile", background_tile())
    for kind in ("std", "accent"):
        for st in ("normal", "hover", "pressed", "disabled"):
            im, m = button(st, kind)
            reg("button_%s_%s" % (kind, st), im, (m,) * 4)
    im, m = focus_ring()
    reg("focus", im, (m,) * 4)
    for st in ("hover", "pressed"):
        im, m = sidebar_button(st)
        reg("sidebar_btn_" + st, im, (m,) * 4)
    for kd in ("normal", "focus", "readonly"):
        im, m = line_edit(kd)
        reg("field_" + kd, im, (m,) * 4)
    for f in (False, True):
        im, mg = search_field(f)
        reg("search_" + ("focus" if f else "normal"), im, mg)
    for kd in ("selected", "unselected", "hover", "disabled"):
        im, mg = tab({"unselected": "normal"}.get(kd, kd))
        reg("tab_" + kd, im, mg)
    im, m = progress_bg()
    reg("progress_bg", im, (m,) * 4)
    for name, acc in (("brass", BRASS), ("olive", OLIVE), ("rust", RUST), ("indigo", INDIGO), ("azure", ramp("#4aa3d8")),
                      ("red", ramp("#d05050")), ("steel", STEEL), ("white", ramp("#ffffff"))):
        im, m = progress_fill(acc)
        reg("progress_fill_" + name, im, (m,) * 4)
    im, mg = slider_track(False)
    reg("slider_track", im, mg)
    im, mg = slider_track(True)
    reg("slider_fill", im, mg)
    im, mg = slider_track(True, ramp("#e6c47a"))
    reg("slider_fill_hl", im, mg)
    for k in ("normal", "highlight", "disabled"):
        reg("slider_grabber_" + k, grabber(k))
    for k in ("track", "grab", "hover", "pressed"):
        im, m = scroll_img(k)
        reg("scroll_" + k, im, (m,) * 4)
    im, mg = separator_h()
    reg("separator_h", im, mg)
    reg("separator_v", im.transpose(Image.ROTATE_90), (mg[1], mg[2], mg[3], mg[0]))
    for chk in (False, True):
        for dis in (False, True):
            suf = ("on" if chk else "off") + ("_dis" if dis else "")
            reg("check_" + suf, check_icon(chk, dis))
            reg("radio_" + suf, check_icon(chk, dis, radio=True))
            reg("switch_" + suf, switch_icon(chk, dis))
    for d in ("down", "up", "left", "right"):
        reg("arrow_" + d, arrow_small(d))
    for i, (rid, r) in enumerate(RARITIES.items()):
        im, m = rarity_card(r, i)
        reg("card_" + rid, im, (m,) * 4)
        im, m = rarity_slot(r, i)
        reg("slot_" + rid, im, (m,) * 4)
    reg("logo", logo())
    reg("vault_door", vault_door())
    reg("empty_chest", empty_chest())
    reg("empty_scroll", empty_scroll())
    reg("empty_shelf", empty_shelf())


def pixel_exact(im: Image.Image) -> bool:
    return all(a in (0, 255) for a in im.tobytes()[3::4])


def main() -> int:
    check = "--check" in sys.argv
    build()
    bad = [n for n, im in IMAGES.items() if not pixel_exact(im)]
    if bad:
        print("ERRORE: pixel con alpha parziale (antialiasing):", ", ".join(bad))
        return 1
    manifest_text = json.dumps(MANIFEST, indent=1, sort_keys=True) + "\n"
    if check:
        diff = 0
        for n, im in IMAGES.items():
            p = OUT / (n + ".png")
            if not p.exists() or Image.open(p).convert("RGBA").tobytes() != im.tobytes():
                print("DIVERSO/MANCANTE:", p.name)
                diff += 1
        mp = OUT / "frames.json"
        if not mp.exists() or mp.read_text() != manifest_text:
            print("DIVERSO: frames.json")
            diff += 1
        print("make_ui_frames --check: %d file, %d differenze, tutti a pixel esatti" % (len(IMAGES), diff))
        return 1 if diff else 0
    OUT.mkdir(parents=True, exist_ok=True)
    for n, im in IMAGES.items():
        im.save(OUT / (n + ".png"), optimize=False)
    (OUT / "frames.json").write_text(manifest_text)
    print("make_ui_frames: %d immagini in %s" % (len(IMAGES), OUT.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
