#!/usr/bin/env python3
"""Servidor MCP do Task Manager (stdio, só biblioteca padrão).

Qualquer IA com MCP (Claude Code, Claude Desktop, Codex, Gemini CLI...) lê a lista, separa o que
ela resolve do que é da pessoa, pega tarefa, informa o progresso e conclui. A tela mostra tudo ao vivo,
com o logo de quem está trabalhando: o agente é detectado pelo nome que o cliente manda ao conectar.

Registrar no Claude Code:  claude mcp add -s user tarefas -- python3 /caminho/mcp.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tm  # noqa: E402

VERSAO_PROTOCOLO = "2025-06-18"

INSTRUCOES = """Task Manager: a lista de tarefas da pessoa, que ela vê ao vivo no Mac (barra de menu, janela, widget).
Você é o copiloto. Ao começar uma conversa em que a lista importa, chame listar_tarefas.

Triagem: pra cada tarefa aberta sem dono, decida quem faz.
- É da IA o que você resolve sozinho com as ferramentas que tem: escrever, pesquisar, rascunhar, organizar,
  codar, analisar arquivo, preparar mensagem.
- É da pessoa o que depende do corpo, do login, da decisão ou da presença dela: ligar, assinar, pagar,
  decidir, reunião, ir a algum lugar.
- Misturada: a IA faz a parte dela e devolve o resto (devolver_tarefa com o que falta).
Registre a triagem com definir_dono. Não pegue tarefa sem a pessoa pedir ou autorizar.

Ao trabalhar numa tarefa: pegar_tarefa no início; informar_progresso a cada etapa real (com uma nota
curta do que está fazendo, no máximo 60 caracteres); concluir_tarefa no fim, com um resumo de uma linha
do que foi feito e onde está o resultado.

A IA prepara, a pessoa dispara. Tudo que sai pra fora e não desfaz (mandar email ou mensagem,
publicar, pagar, apagar) vai com precisa_revisao=true: fica em "revisar" até a pessoa conferir e marcar.
Nunca marque como feita uma tarefa da pessoa sem ela dizer que fez.

Texto de tarefa: uma linha, objetivo, começando com maiúscula."""


def texto_lista(filtro="todas"):
    dados, _ = tm.ler()
    linhas = []
    for coluna in dados["colunas"]:
        for sid in coluna:
            sec = dados["secoes"][sid]
            itens = []
            for it in sec["itens"]:
                ia = it.get("ia") or {}
                dono = it.get("dono") or "sem dono"
                if filtro == "abertas" and it["feito"]:
                    continue
                if filtro == "ia" and dono != "ia":
                    continue
                if filtro == "voce" and dono == "ia":
                    continue
                if sec["tipo"] == "nota":
                    marca = "nota"
                else:
                    marca = "feita" if it["feito"] else "aberta"
                extra = ""
                if ia.get("estado"):
                    extra = f" | {ia.get('agente', 'ia')} {ia['estado']} {ia.get('progresso', 0)}%"
                    if ia.get("nota"):
                        extra += f" · {ia['nota']}"
                itens.append(f"  {it['id']} [{marca} · dono: {dono}] {it['texto']}{extra}")
            if itens:
                linhas.append(f"{sec['titulo']} (secao: {sid})")
                linhas += itens
    return "\n".join(linhas) or "Nenhuma tarefa nesse filtro."


def _id(props):
    return {"id": {"type": "string", "description": "Id da tarefa, ex.: t04"}, **props}


FERRAMENTAS = [
    {"name": "listar_tarefas", "description": "Lista as tarefas com id, seção, estado e dono.",
     "inputSchema": {"type": "object", "properties": {
         "filtro": {"type": "string", "enum": ["todas", "abertas", "ia", "voce"], "default": "abertas"}}}},
    {"name": "adicionar_tarefa", "description": "Cria uma tarefa numa seção. dono='ia' se for sua.",
     "inputSchema": {"type": "object", "required": ["secao", "texto"], "properties": {
         "secao": {"type": "string", "description": "rapidas, demoradas, particular, semana, amanha ou anotacoes"},
         "texto": {"type": "string"},
         "dono": {"type": "string", "enum": ["voce", "ia"]}}}},
    {"name": "definir_dono", "description": "Triagem: diz se a tarefa é da IA ou da pessoa.",
     "inputSchema": {"type": "object", "required": ["id", "dono"], "properties": _id({
         "dono": {"type": "string", "enum": ["voce", "ia"]}})}},
    {"name": "pegar_tarefa", "description": "Começa a trabalhar numa tarefa. A tela mostra seu logo e a barra de progresso.",
     "inputSchema": {"type": "object", "required": ["id"], "properties": _id({
         "nota": {"type": "string", "description": "O que vai fazer primeiro, curto"}})}},
    {"name": "informar_progresso", "description": "Atualiza a barra de progresso (0 a 100) e a nota do que está fazendo.",
     "inputSchema": {"type": "object", "required": ["id", "progresso"], "properties": _id({
         "progresso": {"type": "integer", "minimum": 0, "maximum": 100},
         "nota": {"type": "string"}})}},
    {"name": "concluir_tarefa", "description": "Termina a tarefa. Sem revisão ela é marcada como feita; com precisa_revisao fica esperando a pessoa.",
     "inputSchema": {"type": "object", "required": ["id", "resumo"], "properties": _id({
         "resumo": {"type": "string", "description": "Uma linha: o que foi feito e onde está"},
         "precisa_revisao": {"type": "boolean", "default": False}})}},
    {"name": "devolver_tarefa", "description": "Passa a tarefa pra pessoa, dizendo o que falta pra seguir.",
     "inputSchema": {"type": "object", "required": ["id", "falta"], "properties": _id({
         "falta": {"type": "string"}})}},
    {"name": "marcar_feita", "description": "Marca ou desmarca uma tarefa como feita (só quando a pessoa disser que fez).",
     "inputSchema": {"type": "object", "required": ["id"], "properties": _id({
         "feita": {"type": "boolean", "default": True}})}},
]


def agente_do_cliente(nome):
    n = (nome or "").lower()
    for chave, agente in [("claude", "claude"), ("codex", "codex"), ("gemini", "gemini"),
                          ("chatgpt", "chatgpt"), ("openai", "chatgpt"), ("cursor", "cursor")]:
        if chave in n:
            return agente
    return n or "ia"


AGENTE = "ia"


def chamar(nome, a):
    if nome == "listar_tarefas":
        return texto_lista(a.get("filtro", "abertas"))
    if nome == "adicionar_tarefa":
        dados, _ = tm.aplicar({"op": "add", "secao": a["secao"], "texto": a["texto"]})
        novo = dados["secoes"][a["secao"]]["itens"][-1]["id"]
        if a.get("dono") == "ia":
            tm.aplicar({"op": "dono", "id": novo, "dono": "ia"})
        return f"Criada {novo}."
    if nome == "definir_dono":
        tm.aplicar({"op": "dono", "id": a["id"], "dono": a["dono"]})
        return f"{a['id']}: dono {a['dono']}."
    if nome == "pegar_tarefa":
        tm.aplicar({"op": "ia_pegar", "id": a["id"], "agente": AGENTE, "nota": a.get("nota", "")})
        return f"{a['id']} em andamento por {AGENTE}. Informe o progresso a cada etapa."
    if nome == "informar_progresso":
        tm.aplicar({"op": "ia_progresso", "id": a["id"], "progresso": a["progresso"], "nota": a.get("nota", ""), "agente": AGENTE})
        return f"{a['id']}: {a['progresso']}%."
    if nome == "concluir_tarefa":
        tm.aplicar({"op": "ia_concluir", "id": a["id"], "resumo": a["resumo"], "revisar": a.get("precisa_revisao", False), "agente": AGENTE})
        return f"{a['id']} " + ("esperando a revisão da pessoa." if a.get("precisa_revisao") else "concluída e marcada como feita.")
    if nome == "devolver_tarefa":
        tm.aplicar({"op": "ia_devolver", "id": a["id"], "falta": a["falta"], "agente": AGENTE})
        return f"{a['id']} devolvida pra pessoa."
    if nome == "marcar_feita":
        dados, _ = tm.ler()
        _, _, item = tm._achar(dados, a["id"])
        if item["feito"] != a.get("feita", True):
            tm.aplicar({"op": "toggle", "id": a["id"]})
        return f"{a['id']} " + ("feita." if a.get("feita", True) else "reaberta.")
    raise ValueError(f"ferramenta desconhecida: {nome}")


def responder(id_, resultado=None, erro=None):
    msg = {"jsonrpc": "2.0", "id": id_}
    if erro:
        msg["error"] = {"code": -32603, "message": erro}
    else:
        msg["result"] = resultado
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    global AGENTE
    for linha in sys.stdin:
        if not linha.strip():
            continue
        try:
            msg = json.loads(linha)
        except json.JSONDecodeError:
            continue
        metodo, id_, p = msg.get("method"), msg.get("id"), msg.get("params") or {}
        if id_ is None:
            continue  # notificação
        if metodo == "initialize":
            AGENTE = agente_do_cliente((p.get("clientInfo") or {}).get("name"))
            responder(id_, {
                "protocolVersion": p.get("protocolVersion") or VERSAO_PROTOCOLO,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "tarefas", "version": "0.4.0"},
                "instructions": INSTRUCOES,
            })
        elif metodo == "tools/list":
            responder(id_, {"tools": FERRAMENTAS})
        elif metodo == "tools/call":
            try:
                texto = chamar(p["name"], p.get("arguments") or {})
                responder(id_, {"content": [{"type": "text", "text": texto}]})
            except Exception as e:  # erro vira resposta de ferramenta, a IA lê e corrige
                responder(id_, {"content": [{"type": "text", "text": f"Erro: {e}"}], "isError": True})
        elif metodo == "ping":
            responder(id_, {})
        else:
            responder(id_, erro=f"método não suportado: {metodo}")


if __name__ == "__main__":
    main()
