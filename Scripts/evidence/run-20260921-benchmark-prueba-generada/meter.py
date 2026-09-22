#!/usr/bin/env python3
"""Proxy HTTP que mide exactamente lo que un agente lee y escribe contra un servidor
de automatización. Cuenta tokens reales con cl100k_base sobre lo que viajaría en la
conversación del agente: la línea de petición con su cuerpo, y el cuerpo de la respuesta.

Uso: meter.py <puerto_escucha> <puerto_destino> <archivo_log.jsonl>
"""
import http.server
import http.client
import json
import socketserver
import sys
import threading
import time

import tiktoken

LISTEN, TARGET, LOGFILE = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
ENC = tiktoken.get_encoding("cl100k_base")
LOCK = threading.Lock()


def count(text):
    if not text:
        return 0
    return len(ENC.encode(text, disallowed_special=()))


def record(entry):
    with LOCK:
        with open(LOGFILE, "a") as handle:
            handle.write(json.dumps(entry) + "\n")


class Meter(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "meter"

    def log_message(self, *args):
        pass

    def _proxy(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        started = time.time()
        connection = http.client.HTTPConnection("127.0.0.1", TARGET, timeout=600)
        try:
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "connection")}
            connection.request(method, self.path, body=body or None, headers=headers)
            upstream = connection.getresponse()
            payload = upstream.read()
            status = upstream.status
            content_type = upstream.getheader("Content-Type") or "application/octet-stream"
        except Exception as error:  # el destino puede estar arrancando todavía
            payload = json.dumps({"value": {"error": "proxy_error", "message": str(error)}}).encode()
            status, content_type = 502, "application/json"
        finally:
            connection.close()

        # Lo que el agente realmente lee: texto. Un binario (PNG) se cuenta por su
        # tamaño, no por tokens, porque no entra crudo en la conversación.
        binary = not content_type.startswith(("application/json", "text/", "application/xml"))
        request_text = f"{method} {self.path}\n" + body.decode("utf-8", "replace")
        response_text = "" if binary else payload.decode("utf-8", "replace")
        record({
            "ts": round(started, 3),
            "method": method,
            "path": self.path.split("?")[0],
            "status": status,
            "req_bytes": len(body),
            "resp_bytes": len(payload),
            "req_tokens": count(request_text),
            "resp_tokens": count(response_text),
            "binary": binary,
            "ms": int((time.time() - started) * 1000),
        })

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except BrokenPipeError:
            pass

    def do_GET(self):
        self._proxy("GET")

    def do_POST(self):
        self._proxy("POST")

    def do_DELETE(self):
        self._proxy("DELETE")

    def do_PUT(self):
        self._proxy("PUT")


class Threaded(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


Threaded(("127.0.0.1", LISTEN), Meter).serve_forever()
