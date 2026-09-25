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
Ela funciona como a barra de status de tudo que as IAs estão fazendo. Vale em toda sessão.

Barra de status (sempre):
- Todo trabalho MACRO desta sessão aparece na lista. Macro é o que a pessoa chamaria de tarefa: "ajustar a
  área de membros", "resolver o erro da Amazon", "montar a proposta da Samara". Pergunta rápida, conversa,
  leitura ou comando solto não entram.
- Ao começar um trabalho macro, chame comecar_trabalho com um título curto. Ela acha a tarefa da pessoa que
  corresponde (e você se pendura nela) ou cria uma tarefa macro sua. Se ela devolver candidatas, escolha
  o id certo ou peça pra criar.
- Subtarefa não vira item. Ela vira etapa: informar_progresso com etapa "3/7" e uma nota curta do passo
  (até 60 caracteres), a cada passo real, nunca a cada comando.
- No fim, concluir_tarefa com um resumo de uma linha e, quando houver, o resultado (texto pronto ou
  caminho do arquivo). Se parar no meio, devolver_tarefa dizendo o que falta. Não deixe tarefa em "fazendo"
  quando a sessão termina.

Triagem, quando a pessoa pedir pra organizar a lista: é da IA o que ela resolve sozinha com as ferramentas
que tem (escrever, pesquisar, rascunhar, organizar, codar, analisar); é da pessoa o que depende do corpo,
login, decisão ou presença dela. Registre com definir_dono. Só pegue tarefa da lista que a pessoa não pediu
se ela autorizar.

A IA prepara, a pessoa dispara. Tudo que sai pra fora e não desfaz (mandar email ou mensagem, publicar,
pagar, apagar) vai com precisa_revisao=true e o texto no resultado: fica em "revisar" até a pessoa conferir.
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
    {"name": "comecar_trabalho", "description": "Abre a barra de status de um trabalho macro: acha a tarefa da pessoa que corresponde ou cria uma tarefa macro da IA, e marca como em andamento. Chame no início de todo trabalho macro.",
     "inputSchema": {"type": "object", "required": ["titulo"], "properties": {
         "titulo": {"type": "string", "description": "Título curto do trabalho, como a pessoa escreveria"},
         "id": {"type": "string", "description": "Id de uma tarefa existente, se você já sabe qual é"},
         "criar": {"type": "boolean", "description": "true pra criar tarefa nova sem procurar parecida"},
         "secao": {"type": "string", "description": "Onde criar: rapidas (minutos) ou demoradas (padrão)"},
         "nota": {"type": "string", "description": "O primeiro passo, curto"}}}},
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
         "etapa": {"type": "string", "description": "Etapa atual, ex.: 3/7"},
         "nota": {"type": "string", "description": "O passo atual, até 60 caracteres"}})}},
    {"name": "concluir_tarefa", "description": "Termina a tarefa. Sem revisão ela é marcada como feita; com precisa_revisao fica esperando a pessoa.",
     "inputSchema": {"type": "object", "required": ["id", "resumo"], "properties": _id({
         "resumo": {"type": "string", "description": "Uma linha: o que foi feito e onde está"},
         "resultado": {"type": "string", "description": "O texto pronto (mensagem, resposta) ou o caminho do arquivo, pra pessoa ver sem abrir a sessão"},
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


def comecar(a):
    if a.get("id"):
        alvo = a["id"]
    elif not a.get("criar"):
        dados, _ = tm.ler()
        cand = tm.parecidas(dados, a["titulo"])
        certeira = cand and cand[0][0] >= 0.9 and (len(cand) == 1 or cand[0][0] - cand[1][0] >= 0.2)
        if cand and not certeira:
            linhas = "\n".join(f"  {it['id']} {it['texto']} (parecida {n})" for n, _, it in cand[:5])
            return ("Achei tarefas parecidas. Chame de novo com id=<a certa>, ou criar=true se nenhuma for esse trabalho:\n" + linhas), None
        alvo = cand[0][2]["id"] if cand else None
    else:
        alvo = None
    criada = alvo is None
    if criada:
        secao = a.get("secao") or "demoradas"
        dados, _ = tm.aplicar({"op": "add", "secao": secao, "texto": a["titulo"]})
        alvo = dados["secoes"][secao]["itens"][-1]["id"]
    tm.aplicar({"op": "ia_pegar", "id": alvo, "agente": AGENTE, "nota": a.get("nota", "")})
    return (f"{'Criei' if criada else 'Peguei'} {alvo}. Informe o progresso por etapa e conclua no fim."), alvo


def chamar(nome, a):
    if nome == "comecar_trabalho":
        return comecar(a)[0]
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
        tm.aplicar({"op": "ia_progresso", "id": a["id"], "progresso": a["progresso"], "nota": a.get("nota", ""),
                    "etapa": a.get("etapa", ""), "agente": AGENTE})
        return f"{a['id']}: {a['progresso']}%."
    if nome == "concluir_tarefa":
        tm.aplicar({"op": "ia_concluir", "id": a["id"], "resumo": a["resumo"], "resultado": a.get("resultado", ""),
                    "revisar": a.get("precisa_revisao", False), "agente": AGENTE})
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
                "serverInfo": {"name": "tarefas", "version": "0.5.0"},
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
