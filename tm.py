#!/usr/bin/env python3
"""Núcleo do Task Manager: lê, altera e grava dados/tarefas.json.

Usado pelo servidor e direto pelo terminal:
  python3 tm.py lista
  python3 tm.py add demoradas "Texto da tarefa"
  python3 tm.py check t04        (alterna feito/aberto)
  python3 tm.py edit t04 "Texto novo"
  python3 tm.py rm t04
  python3 tm.py move t04 amanha [posição]
  python3 tm.py limpar           (tira tudo o que está feito)

Copiloto de IA (o mesmo que o MCP em mcp.py faz):
  python3 tm.py dono t04 ia|voce
  python3 tm.py pegar t04 claude ["o que vai fazer"]
  python3 tm.py progresso t04 40 "lendo a conversa"
  python3 tm.py concluir t04 "o que foi feito" [revisar]
  python3 tm.py devolver t04 "o que falta pra IA seguir"
  python3 tm.py comecar claude "Título do trabalho macro" [secao]   (acha a tarefa parecida ou cria)
  python3 tm.py perguntar t04 "Qual o código SMS?" [etapa]          (a IA para e espera você)
  python3 tm.py responder t04 "482913"
  python3 tm.py voltar t04 ["comentário"]    (devolve à IA: refazer ou seguir depois de destravar)
  python3 tm.py resumo           (o que entra no início de cada sessão de IA)
"""
import fcntl
import hashlib
import json
import os
import sys
import tempfile
import time
import unicodedata
from contextlib import contextmanager
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
ARQUIVO = RAIZ / "dados" / "tarefas.json"
EXEMPLO = RAIZ / "dados" / "exemplo.json"
TRAVA = RAIZ / "dados" / ".trava"

# Primeira execução: começa a partir do exemplo.
if not ARQUIVO.exists():
    ARQUIVO.write_bytes(EXEMPLO.read_bytes())


@contextmanager
def travado():
    with open(TRAVA, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def ler():
    bruto = ARQUIVO.read_bytes()
    return json.loads(bruto), hashlib.sha1(bruto).hexdigest()[:12]


def gravar(dados):
    texto = json.dumps(dados, ensure_ascii=False, indent=2) + "\n"
    fd, tmp = tempfile.mkstemp(dir=ARQUIVO.parent, suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(texto)
    os.replace(tmp, ARQUIVO)
    return hashlib.sha1(texto.encode()).hexdigest()[:12]


def _achar(dados, id_):
    for sid, sec in dados["secoes"].items():
        for i, item in enumerate(sec["itens"]):
            if item["id"] == id_:
                return sid, i, item
    raise KeyError(f"tarefa {id_} não existe")


PALAVRAS_VAZIAS = {"de", "da", "do", "das", "dos", "e", "o", "a", "os", "as", "um", "uma", "pra", "para",
                   "com", "no", "na", "nos", "nas", "em", "por", "que", "se", "ao", "the", "and"}


def _palavras(texto):
    t = unicodedata.normalize("NFKD", texto.lower())
    t = "".join(c if c.isalnum() else " " for c in t if not unicodedata.combining(c))
    return {p for p in t.split() if len(p) > 2 and p not in PALAVRAS_VAZIAS}


def parecidas(dados, titulo, minimo=0.5):
    """Tarefas abertas com texto parecido com o título, da mais parecida pra menos: [(nota, sid, item)]."""
    alvo = _palavras(titulo)
    achadas = []
    for sid, sec in dados["secoes"].items():
        if sec["tipo"] != "check":
            continue
        for it in sec["itens"]:
            if it["feito"]:
                continue
            p = _palavras(it["texto"])
            if not p or not alvo:
                continue
            nota = len(alvo & p) / min(len(alvo), len(p))
            if nota >= minimo:
                achadas.append((round(nota, 2), sid, it))
    return sorted(achadas, key=lambda x: -x[0])


def _novo_id(dados):
    usados = {it["id"] for s in dados["secoes"].values() for it in s["itens"]}
    n = len(usados) + 1
    while f"t{n:02d}" in usados:
        n += 1
    return f"t{n:02d}"


def aplicar(op):
    """Aplica uma operação e devolve (dados, versao)."""
    with travado():
        dados, _ = ler()
        tipo = op.get("op")
        agora = time.strftime("%Y-%m-%dT%H:%M:%S")

        if tipo == "add":
            sec = dados["secoes"][op["secao"]]
            texto = op["texto"].strip()
            if not texto:
                raise ValueError("texto vazio")
            item = {"id": _novo_id(dados), "texto": texto, "feito": False, "criado": agora}
            pos = op.get("pos")
            sec["itens"].insert(len(sec["itens"]) if pos is None else int(pos), item)
        elif tipo == "toggle":
            _, _, item = _achar(dados, op["id"])
            item["feito"] = not item["feito"]
            if item["feito"]:
                item["feito_em"] = agora
                if item.get("ia", {}).get("estado") == "revisar":
                    item["ia"]["estado"] = "concluida"
            else:
                item.pop("feito_em", None)
        elif tipo == "edit":
            texto = op["texto"].strip()
            if not texto:
                raise ValueError("texto vazio")
            _, _, item = _achar(dados, op["id"])
            item["texto"] = texto
        elif tipo == "delete":
            sid, i, _ = _achar(dados, op["id"])
            dados["secoes"][sid]["itens"].pop(i)
        elif tipo == "move":
            sid, i, item = _achar(dados, op["id"])
            dados["secoes"][sid]["itens"].pop(i)
            destino = dados["secoes"][op["secao"]]["itens"]
            pos = op.get("pos")
            destino.insert(len(destino) if pos is None else min(int(pos), len(destino)), item)
        # ---- copiloto de IA: item["dono"] = "ia" e item["ia"] = {agente, estado, progresso, nota} ----
        elif tipo == "dono":
            _, _, item = _achar(dados, op["id"])
            if op["dono"] == "ia":
                item["dono"] = "ia"
                item.setdefault("ia", {"estado": "fila", "progresso": 0})
            else:
                item.pop("dono", None)
                item.pop("ia", None)
        elif tipo == "ia_pegar":
            _, _, item = _achar(dados, op["id"])
            item["dono"] = "ia"
            item["feito"] = False
            item["ia"] = {"agente": op.get("agente") or "ia", "estado": "fazendo", "progresso": 0,
                          "nota": (op.get("nota") or "").strip(), "inicio": agora, "atualizado": agora}
        elif tipo == "ia_progresso":
            _, _, item = _achar(dados, op["id"])
            ia = item.setdefault("ia", {"agente": op.get("agente") or "ia"})
            item["dono"] = "ia"
            ia["estado"] = "fazendo"
            ia["progresso"] = max(0, min(100, int(op["progresso"])))
            if op.get("nota"):
                ia["nota"] = op["nota"].strip()
            if op.get("agente"):
                ia["agente"] = op["agente"]
            if op.get("etapa"):
                ia["etapa"] = str(op["etapa"]).strip()
            ia["atualizado"] = agora
        elif tipo == "ia_concluir":
            _, _, item = _achar(dados, op["id"])
            ia = item.setdefault("ia", {"agente": op.get("agente") or "ia"})
            item["dono"] = "ia"
            ia.update(progresso=100, nota=(op.get("resumo") or "").strip(), fim=agora, atualizado=agora)
            ia.pop("etapa", None)
            if op.get("resultado"):
                ia["resultado"] = op["resultado"].strip()
            if op.get("revisar"):
                ia["estado"] = "revisar"           # fica aberta até você conferir e marcar
            else:
                ia["estado"] = "concluida"
                item["feito"] = True
                item["feito_em"] = agora
        elif tipo == "ia_devolver":
            _, _, item = _achar(dados, op["id"])
            ia = item.setdefault("ia", {"agente": op.get("agente") or "ia"})
            item["dono"] = "voce"
            ia.update(estado="devolvida", nota=(op.get("falta") or "").strip(), fim=agora, atualizado=agora)
        elif tipo == "ia_perguntar":
            _, _, item = _achar(dados, op["id"])
            ia = item.setdefault("ia", {"agente": op.get("agente") or "ia", "progresso": 0})
            item["dono"] = "ia"
            ia.update(estado="aguardando", pergunta=op["pergunta"].strip(), atualizado=agora)
            ia.pop("resposta", None)
            if op.get("agente"):
                ia["agente"] = op["agente"]
            if op.get("etapa"):
                ia["etapa"] = str(op["etapa"]).strip()
        elif tipo == "responder":
            _, _, item = _achar(dados, op["id"])
            ia = item.get("ia") or {}
            if ia.get("estado") != "aguardando":
                raise ValueError("essa tarefa não está esperando resposta")
            texto = op["resposta"].strip()
            if not texto:
                raise ValueError("resposta vazia")
            ia.update(estado="fazendo", resposta=texto, respondido=agora, atualizado=agora,
                      nota=f"respondido: {ia.get('pergunta', '')}"[:80])
        elif tipo == "voltar_ia":
            # Aprovar → "devolver à IA" pra refazer; Destravar → "resolvi, pode seguir"
            _, _, item = _achar(dados, op["id"])
            ia = item.setdefault("ia", {"agente": "ia"})
            item["dono"] = "ia"
            item["feito"] = False
            ia.update(estado="fila", progresso=0, atualizado=agora, nota="",
                      comentario=(op.get("comentario") or "").strip())
            for k in ("resultado", "pergunta", "etapa", "fim"):
                ia.pop(k, None)
        elif tipo == "limpar":
            for sec in dados["secoes"].values():
                sec["itens"] = [it for it in sec["itens"] if not it["feito"]]
        else:
            raise ValueError(f"operação desconhecida: {tipo}")

        return dados, gravar(dados)


def resumo(agora=None):
    """Texto curto pro começo de cada sessão de IA: o que está rodando, o que espera a pessoa, o que está parado."""
    dados, _ = ler()
    agora = agora or time.time()
    rodando, esperando, parados, abertas = [], [], [], 0
    for sec in dados["secoes"].values():
        if sec["tipo"] != "check":
            continue
        for it in sec["itens"]:
            if it["feito"]:
                continue
            abertas += 1
            ia = it.get("ia") or {}
            est = ia.get("estado")
            quem = ia.get("agente", "ia")
            if est == "fazendo":
                try:
                    parado = agora - time.mktime(time.strptime(ia.get("atualizado") or ia.get("inicio"), "%Y-%m-%dT%H:%M:%S"))
                except (TypeError, ValueError):
                    parado = 0
                linha = f"{it['id']} {it['texto']} ({quem}, {ia.get('progresso', 0)}%)"
                (parados if parado > 30 * 60 else rodando).append(linha + (f", sem notícia há {int(parado // 60)} min" if parado > 30 * 60 else ""))
            elif est in ("revisar", "devolvida", "aguardando"):
                esperando.append(f"{it['id']} {it['texto']} ({est})")
            elif est == "fila" and ia.get("comentario"):
                rodando.append(f"{it['id']} {it['texto']} (voltou pra IA: \"{ia['comentario']}\")")
    partes = [f"Task Manager (MCP tarefas): {abertas} tarefas abertas."]
    if rodando:
        partes.append("IA fazendo agora: " + "; ".join(rodando) + ".")
    if parados:
        partes.append("Paradas sem atualização (retome ou devolva): " + "; ".join(parados) + ".")
    if esperando:
        partes.append("Esperando a pessoa: " + "; ".join(esperando) + ".")
    partes.append("Regra: todo trabalho macro desta sessão aparece na lista. Ao começar, chame comecar_trabalho "
                  "(acha a tarefa da pessoa ou cria uma macro); atualize com informar_progresso a cada etapa real; "
                  "feche com concluir_tarefa. Subtarefa não vira item, vira etapa. Pergunta rápida ou conversa não conta.")
    return "\n".join(partes)


def _lista():
    dados, _ = ler()
    for coluna in dados["colunas"]:
        for sid in coluna:
            sec = dados["secoes"][sid]
            print(f"\n{sec['titulo'].upper()}  [{sid}]")
            for it in sec["itens"]:
                marca = "-" if sec["tipo"] == "nota" else ("[x]" if it["feito"] else "[ ]")
                ia = it.get("ia")
                extra = ""
                if ia:
                    extra = f"  ← {ia.get('agente', 'ia')}: {ia.get('estado')} {ia.get('progresso', 0)}%"
                    if ia.get("nota"):
                        extra += f" · {ia['nota']}"
                elif it.get("dono") == "ia":
                    extra = "  ← pra IA"
                print(f"  {marca} {it['id']}  {it['texto']}{extra}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] == "lista":
        _lista()
        sys.exit()
    if a[0] == "resumo":
        print(resumo())
        sys.exit()
    if a[0] == "comecar":
        dados, _ = ler()
        achadas = [x for x in parecidas(dados, a[2]) if x[0] >= 0.75]
        if achadas:
            alvo = achadas[0][2]["id"]
        else:
            secao = a[3] if len(a) > 3 else "demoradas"
            dados, _ = aplicar({"op": "add", "secao": secao, "texto": a[2]})
            alvo = dados["secoes"][secao]["itens"][-1]["id"]
        aplicar({"op": "ia_pegar", "id": alvo, "agente": a[1]})
        print(alvo)
        sys.exit()
    cmd = a[0]
    ops = {
        "add": lambda: {"op": "add", "secao": a[1], "texto": a[2]},
        "check": lambda: {"op": "toggle", "id": a[1]},
        "edit": lambda: {"op": "edit", "id": a[1], "texto": a[2]},
        "rm": lambda: {"op": "delete", "id": a[1]},
        "move": lambda: {"op": "move", "id": a[1], "secao": a[2], "pos": a[3] if len(a) > 3 else None},
        "limpar": lambda: {"op": "limpar"},
        "dono": lambda: {"op": "dono", "id": a[1], "dono": a[2]},
        "pegar": lambda: {"op": "ia_pegar", "id": a[1], "agente": a[2], "nota": a[3] if len(a) > 3 else ""},
        "progresso": lambda: {"op": "ia_progresso", "id": a[1], "progresso": a[2], "nota": a[3] if len(a) > 3 else "",
                              "etapa": a[4] if len(a) > 4 else ""},
        "concluir": lambda: {"op": "ia_concluir", "id": a[1], "resumo": a[2], "revisar": len(a) > 3 and a[3] == "revisar"},
        "devolver": lambda: {"op": "ia_devolver", "id": a[1], "falta": a[2]},
        "perguntar": lambda: {"op": "ia_perguntar", "id": a[1], "pergunta": a[2], "etapa": a[3] if len(a) > 3 else ""},
        "responder": lambda: {"op": "responder", "id": a[1], "resposta": a[2]},
        "voltar": lambda: {"op": "voltar_ia", "id": a[1], "comentario": a[2] if len(a) > 2 else ""},
    }
    if cmd not in ops:
        sys.exit(__doc__)
    aplicar(ops[cmd]())
    _lista()
