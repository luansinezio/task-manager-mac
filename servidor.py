#!/usr/bin/env python3
"""Servidor local do Task Manager. Só biblioteca padrão.

  python3 servidor.py          → http://localhost:8790
"""
import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import tm

PORTA = int(os.environ.get("TM_PORTA", "8790"))
PUBLICO = Path(__file__).resolve().parent / "public"


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLICO), **kwargs)

    def log_message(self, *args):
        pass

    def _json(self, codigo, corpo):
        bruto = json.dumps(corpo, ensure_ascii=False).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(bruto)))
        self.end_headers()
        self.wfile.write(bruto)

    def do_GET(self):
        if self.path.startswith("/api/tarefas"):
            dados, versao = tm.ler()
            return self._json(200, {"versao": versao, "dados": dados})
        return super().do_GET()

    def do_POST(self):
        if self.path != "/api/op":
            return self._json(404, {"erro": "rota não existe"})
        try:
            tamanho = int(self.headers.get("Content-Length", 0))
            op = json.loads(self.rfile.read(tamanho))
            dados, versao = tm.aplicar(op)
            return self._json(200, {"versao": versao, "dados": dados})
        except (KeyError, ValueError) as e:
            dados, versao = tm.ler()
            return self._json(400, {"erro": str(e), "versao": versao, "dados": dados})


if __name__ == "__main__":
    print(f"Task Manager em http://localhost:{PORTA}")
    ThreadingHTTPServer(("127.0.0.1", PORTA), Handler).serve_forever()
