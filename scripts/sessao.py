#!/usr/bin/env python3
"""Gancho de início de sessão do Claude Code: injeta o resumo do Task Manager e a regra da barra de status.

Instalado por scripts/conectar-ia.sh em ~/.claude/settings.json (hooks.SessionStart). Nunca falha a sessão:
se a lista não puder ser lida, sai quieto.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
try:
    import tm
    texto = tm.resumo()
except Exception:
    sys.exit(0)

print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": texto}}, ensure_ascii=False))
