#!/usr/bin/env python3
"""Genera game/assets/fonts/VaultfallSymbols-Regular.ttf: sottoinsieme di Noto Sans Symbols2 (SIL OFL 1.1).

Contiene solo i blocchi di simboli usati dal gioco (frecce, forme geometriche, simboli vari, dingbat, clessidra, lucchetto,
scudo) e ha metriche verticali ridotte: come font di ripiego, un font con interlinea alta (Noto Symbols2: 1,7 em) gonfierebbe
ogni riga di testo (l'altezza di una FontVariation e' il massimo della catena dei ripieghi). Il sottoinsieme e' una versione
modificata: per la OFL e' rinominato "Vaultfall Symbols"; copyright e licenza originali restano nel file e in
OFL-VaultfallSymbols.txt. Sorgente: tools/fontsrc/NotoSansSymbols2-Regular.ttf (notofonts.github.io, cartella
fonts/NotoSansSymbols2/googlefonts/ttf).
Uso: python3 -I tools/make_symbol_font.py   (richiede fonttools)
"""
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "fontsrc" / "NotoSansSymbols2-Regular.ttf"
OUT = ROOT / "game" / "assets" / "fonts" / "VaultfallSymbols-Regular.ttf"
RANGES = [(0x2190, 0x21FF), (0x2300, 0x23FF), (0x25A0, 0x25FF), (0x2600, 0x26FF), (0x2700, 0x27BF),
          (0x1F512, 0x1F512), (0x1F6E1, 0x1F6E1)]


def main() -> None:
    cps = [c for a, b in RANGES for c in range(a, b + 1)]
    opts = subset.Options()
    opts.layout_features = []
    opts.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    opts.notdef_outline = True
    opts.glyph_names = False
    font = TTFont(SRC)
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=cps)
    sub.subset(font)
    upem = font["head"].unitsPerEm
    asc, desc = int(upem * 0.9), int(upem * 0.2)      # piu' basse di Atkinson (0,984 / 0,316): non alzano la riga
    font["hhea"].ascent, font["hhea"].descent, font["hhea"].lineGap = asc, -desc, 0
    os2 = font["OS/2"]
    os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = asc, -desc, 0
    os2.usWinAscent, os2.usWinDescent = asc, desc
    for rec in font["name"].names:
        if rec.nameID in (1, 16):
            rec.string = "Vaultfall Symbols"
        elif rec.nameID == 4:
            rec.string = "Vaultfall Symbols Regular"
        elif rec.nameID == 6:
            rec.string = "VaultfallSymbols-Regular"
        elif rec.nameID == 3:
            rec.string = "VaultfallSymbols-Regular;subset-of-NotoSansSymbols2"
    font.save(OUT)
    print(f"{OUT} ({OUT.stat().st_size} byte, {len(font.getBestCmap())} caratteri)")


if __name__ == "__main__":
    main()
