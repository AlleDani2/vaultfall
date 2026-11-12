"""Hook PreToolUse (Edit/Write): BLOCCA le modifiche manuali ai dati generati.

data/*.json e game/data/*.json si creano solo con tools/generate_data.py e tools/sync_data.py.
Codice di uscita 2 = Claude Code annulla la modifica e mostra il messaggio a Claude.
Se in /hooks questo hook risultasse in errore (versioni di Claude Code senza la "forma exec" con "args"),
sostituire in .claude/settings.json la voce con:  "command": "python \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard_data.py\""
"""
import json, sys

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
path = str((payload.get("tool_input") or {}).get("file_path", "")).replace("\\", "/")
if path.endswith(".json") and "/game/data/" in path:
    print(f"BLOCCATO: {path} e' una COPIA di data/ (la sovrascrive tools/sync_data.py). "
          "Modifica la fonte in tools/gamedata/*.py e poi esegui la pipeline (/data-pipeline).", file=sys.stderr)
    sys.exit(2)
if path.endswith(".json") and "/data/" in path and "/tests/" not in path:
    print(f"BLOCCATO: {path} e' un file GENERATO. Cambia tools/gamedata/*.py, poi esegui: python tools/generate_data.py, "
          "python tools/validate_data.py, python tools/balance_sim.py, python tools/sync_data.py (/data-pipeline).", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
