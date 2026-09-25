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
"""
import fcntl
import hashlib
import json
import os
import sys
import tempfile
import time
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
                          "nota": (op.get("nota") or "").strip(), "inicio": agora}
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
        elif tipo == "ia_concluir":
            _, _, item = _achar(dados, op["id"])
            ia = item.setdefault("ia", {"agente": op.get("agente") or "ia"})
            item["dono"] = "ia"
            ia.update(progresso=100, nota=(op.get("resumo") or "").strip(), fim=agora)
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
            ia.update(estado="devolvida", nota=(op.get("falta") or "").strip(), fim=agora)
        elif tipo == "limpar":
            for sec in dados["secoes"].values():
                sec["itens"] = [it for it in sec["itens"] if not it["feito"]]
        else:
            raise ValueError(f"operação desconhecida: {tipo}")

        return dados, gravar(dados)


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
        "progresso": lambda: {"op": "ia_progresso", "id": a[1], "progresso": a[2], "nota": a[3] if len(a) > 3 else ""},
        "concluir": lambda: {"op": "ia_concluir", "id": a[1], "resumo": a[2], "revisar": len(a) > 3 and a[3] == "revisar"},
        "devolver": lambda: {"op": "ia_devolver", "id": a[1], "falta": a[2]},
    }
    if cmd not in ops:
        sys.exit(__doc__)
    aplicar(ops[cmd]())
    _lista()
