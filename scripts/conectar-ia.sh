#!/bin/bash
# Conecta o MCP do Task Manager às IAs instaladas: Claude Code, Claude Desktop, Codex e Gemini CLI.
# Também faz toda sessão começar sabendo da lista: gancho SessionStart no Claude Code e um bloco nas
# instruções globais do Codex (~/.codex/AGENTS.md) e do Gemini (~/.gemini/GEMINI.md).
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
raiz = Path(mcp).parent
gancho = f'"{py}" "{raiz / "scripts" / "sessao.py"}"'

# Claude Code: gancho de início de sessão
cfg_claude = home / ".claude/settings.json"
if cfg_claude.parent.exists():
    cfg = json.loads(cfg_claude.read_text()) if cfg_claude.exists() and cfg_claude.read_text().strip() else {}
    inicio = cfg.setdefault("hooks", {}).setdefault("SessionStart", [])
    nosso = lambda g: any("sessao.py" in h.get("command", "") and "task-manager" in h.get("command", "") for h in g.get("hooks", []))
    tem = any(nosso(g) for g in inicio)
    if remover:
        if tem:
            cfg["hooks"]["SessionStart"] = [g for g in inicio if not nosso(g)]
            if not cfg["hooks"]["SessionStart"]:
                del cfg["hooks"]["SessionStart"]
            if not cfg["hooks"]:
                del cfg["hooks"]
            cfg_claude.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"); print("     Claude Code, início de sessão: removido")
    elif tem:
        print("     Claude Code, início de sessão: já ligado")
    else:
        inicio.append({"hooks": [{"type": "command", "command": gancho, "timeout": 10}]})
        cfg_claude.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"); print("     Claude Code, início de sessão: ligado")

# Codex e Gemini: bloco nas instruções globais
INI, FIM = "<!-- task-manager:inicio -->", "<!-- task-manager:fim -->"
BLOCO = f"""{INI}
## Task Manager: barra de status do trabalho

A lista de tarefas da pessoa fica no MCP `tarefas` e ela acompanha ao vivo no Mac.
- No início de cada sessão, chame listar_tarefas (ou rode `{py} {raiz / "tm.py"} resumo`) pra saber o que está rodando e o que espera a pessoa.
- Todo trabalho macro desta sessão aparece na lista: comece com comecar_trabalho, atualize com informar_progresso (etapa "3/7" e nota curta) a cada passo real, feche com concluir_tarefa. Subtarefa vira etapa, não item. Conversa e pergunta rápida não entram.
- Tudo que sai pra fora (email, mensagem, publicação, pagamento) vai com precisa_revisao=true e o texto no resultado.
{FIM}
"""
for nome, arq in [("Codex", home / ".codex/AGENTS.md"), ("Gemini CLI", home / ".gemini/GEMINI.md")]:
    if not arq.parent.exists():
        continue
    texto = arq.read_text() if arq.exists() else ""
    tem = INI in texto
    if tem:
        texto = re.sub(re.escape(INI) + r".*?" + re.escape(FIM) + r"\n?", "", texto, flags=re.S)
    if remover:
        if tem:
            arq.write_text(texto); print(f"     {nome}, instruções globais: removido")
        continue
    arq.write_text((texto.rstrip("\n") + "\n\n" if texto.strip() else "") + BLOCO)
    print(f"     {nome}, instruções globais: " + ("atualizado" if tem else "ligado"))

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
