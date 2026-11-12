#!/usr/bin/env python3
"""Minimal GDScript sanity check (no Godot needed).

This is NOT a parser. It catches the cheap mistakes that break a script before Godot even starts:
unbalanced (), [], {} (strings and comments are skipped), unterminated strings, and indentation that mixes
tabs and spaces on the same line. For real verification use Godot itself:
    godot --headless --path game --import        (then run the GUT tests, see README)

Usage: python tools/gd_lint.py [PATH ...]      (default: game/)      Exit code 0 = no problems.
"""
import os
import sys

PAIRS = {")": "(", "]": "[", "}": "{"}


def check_text(text: str) -> list[tuple[int, str]]:
    problems: list[tuple[int, str]] = []
    stack: list[tuple[str, int]] = []
    i, n, line = 0, len(text), 1
    line_start = True
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            line_start = True
            i += 1
            continue
        if line_start:
            j = i
            while j < n and text[j] in " \t":
                j += 1
            ind = text[i:j]
            if " \t" in ind:
                problems.append((line, "a tab after a space in the indentation"))
            line_start = False
        if c == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c in "\"'":
            raw = i > 0 and text[i - 1] in "rR" and (i < 2 or not (text[i - 2].isalnum() or text[i - 2] == "_"))
            q = c
            triple = text[i:i + 3] == q * 3
            start_line = line
            i += 3 if triple else 1
            closed = False
            while i < n:
                d = text[i]
                if d == "\\" and not raw:
                    if text[i + 1:i + 2] == "\n":
                        line += 1
                    i += 2
                    continue
                if triple:
                    if text[i:i + 3] == q * 3:
                        i += 3
                        closed = True
                        break
                else:
                    if d == q:
                        i += 1
                        closed = True
                        break
                    if d == "\n":
                        break
                if d == "\n":
                    line += 1
                i += 1
            if not closed:
                problems.append((start_line, "unterminated string"))
            continue
        if c in "([{":
            stack.append((c, line))
        elif c in ")]}":
            if not stack or stack[-1][0] != PAIRS[c]:
                problems.append((line, f"unexpected '{c}'"))
            else:
                stack.pop()
        i += 1
    for c, ln in stack:
        problems.append((ln, f"'{c}' never closed"))
    return problems


def iter_files(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for root, dirs, files in os.walk(p):
            dirs[:] = [d for d in dirs if d not in (".git", ".godot", "addons")]  # addons = third-party (GUT)
            for f in sorted(files):
                if f.endswith(".gd"):
                    yield os.path.join(root, f)


def main(argv: list[str]) -> int:
    paths = argv or ["game"]
    bad = total = 0
    for f in iter_files(paths):
        total += 1
        with open(f, encoding="utf-8", errors="replace") as fh:
            probs = check_text(fh.read())
        for ln, msg in probs:
            bad += 1
            print(f"{f}:{ln}: {msg}")
    print(f"gd_lint: {total} files, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
