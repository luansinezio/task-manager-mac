#!/bin/bash
# Conecta o MCP do Task Manager às IAs instaladas: Claude Code, Claude Desktop, Codex e Gemini CLI.
# Pode rodar de novo sem duplicar. Pra tirar: scripts/conectar-ia.sh --remover
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY="$(command -v python3)"
MCP="$DIR/mcp.py"
REMOVER="$1"

# Claude Code
if command -v claude >/dev/null; then
  if [ "$REMOVER" = "--remover" ]; then
    claude mcp remove -s user tarefas >/dev/null 2>&1 && echo "     Claude Code: removido"
  elif claude mcp get tarefas >/dev/null 2>&1; then
    echo "     Claude Code: já conectado"
  else
    claude mcp add -s user tarefas -- "$PY" "$MCP" >/dev/null && echo "     Claude Code: conectado"
  fi
fi

# Claude Desktop, Codex e Gemini: arquivos de configuração
"$PY" - "$PY" "$MCP" "$REMOVER" <<'PYEOF'
import json, re, sys
from pathlib import Path
py, mcp, remover = sys.argv[1], sys.argv[2], sys.argv[3] == "--remover"
home = Path.home()

def json_mcp(nome, arq):
    if not arq.parent.exists():
        return
    cfg = json.loads(arq.read_text()) if arq.exists() and arq.read_text().strip() else {}
    servers = cfg.setdefault("mcpServers", {})
    if remover:
        if servers.pop("tarefas", None) is not None:
            arq.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"); print(f"     {nome}: removido")
        return
    novo = {"command": py, "args": [mcp]}
    if servers.get("tarefas") == novo:
        print(f"     {nome}: já conectado"); return
    servers["tarefas"] = novo
    arq.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    print(f"     {nome}: conectado" + (" (reabra o app)" if "Desktop" in nome else ""))

json_mcp("Claude Desktop", home / "Library/Application Support/Claude/claude_desktop_config.json")
json_mcp("Gemini CLI", home / ".gemini/settings.json")

codex = home / ".codex/config.toml"
if codex.parent.exists():
    texto = codex.read_text() if codex.exists() else ""
    bloco = re.compile(r"\n?\[mcp_servers\.tarefas\]\n(?:(?!\[).*\n?)*")
    if remover:
        if bloco.search(texto):
            codex.write_text(bloco.sub("\n", texto)); print("     Codex: removido")
    elif "[mcp_servers.tarefas]" in texto:
        print("     Codex: já conectado")
    else:
        codex.write_text(texto.rstrip("\n") + f'\n\n[mcp_servers.tarefas]\ncommand = "{py}"\nargs = ["{mcp}"]\n')
        print("     Codex: conectado")
PYEOF
