#!/usr/bin/env python3
"""Measured local HTTP proxy with external, non-negotiable evaluation limits.

Wire token accounting matches the historical meter.py (cl100k_base).
Control events are separate; cleanup remains available after a stop.
"""
import argparse
import hashlib
import http.client
import http.server
import json
from pathlib import Path
import threading
import time


class Limits:
    def __init__(self, calls=80, seconds=480, strict=False):
        self.max_calls, self.seconds, self.strict = calls, seconds, strict
        self.started = None
        self.calls = 0
        self.reason = None
        self.last_error = None
        self.errors = 0
        self.last_write = None
        self.writes = 0
        self.last_read = None
        self.reads = 0

    def stop(self, reason):
        if self.reason is None:
            self.reason = reason

    def before(self, now, method, path, body):
        if method == 'DELETE' and path.startswith('/session/'):
            return True
        if self.started is None:
            self.started = now
        if now - self.started >= self.seconds:
            self.stop('time_limit')
        if self.calls >= self.max_calls:
            self.stop('call_limit')
        if self.reason:
            return False
        if method in ('POST', 'PUT') and path != '/session' and not path.endswith(('/element', '/elements')):
            key = (method, path, hashlib.sha256(body).hexdigest())
            self.writes = self.writes + 1 if key == self.last_write else 1
            self.last_write = key
            if self.writes > 3:
                self.stop('repeated_write')
                return False
        self.calls += 1
        return True

    def after(self, method, path, status, payload):
        if method == 'DELETE':
            return
        if self.strict and status >= 500:
            self.stop('cuyscout_server_error')
        if status >= 400:
            key = (method, path, status)
            self.errors = self.errors + 1 if key == self.last_error else 1
            self.last_error = key
            if self.errors >= 3:
                self.stop('repeated_error')
        elif method not in ('GET',):
            self.last_error, self.errors = None, 0
        if method == 'GET' and ('/observe' in path or path.endswith('/source')):
            # CuyScout changed is request-relative, not a new screen; compare stateId.
            try:
                value = json.loads(payload).get('value', {})
                fingerprint = value.get('stateId') if isinstance(value, dict) else None
            except (ValueError, AttributeError):
                fingerprint = None
            key = (path.split('?')[0], fingerprint or hashlib.sha256(payload).hexdigest())
            self.reads = self.reads + 1 if key == self.last_read else 1
            self.last_read = key
            if self.reads >= 6:
                self.stop('unchanged_screen_limit')


def serve(args):
    import tiktoken
    encoding = tiktoken.get_encoding('cl100k_base')
    limits = Limits(args.max_calls, args.max_seconds, args.strict)
    lock = threading.Lock()
    # Refuse to silently append another attempt to an existing measurement.
    log = open(args.log, 'x')
    control = open(str(args.log) + '.control.jsonl', 'x')
    reported = None

    def event(kind, **data):
        control.write(json.dumps({'ts': time.time(), 'event': kind, **data}) + '\n')
        control.flush()

    def report_stop():
        nonlocal reported
        if limits.reason and reported is None:
            reported = limits.reason
            event('stopped', reason=reported, calls=limits.calls)

    def watchdog():
        while True:
            time.sleep(0.5)
            with lock:
                if limits.started is not None and time.monotonic() - limits.started >= limits.seconds:
                    limits.stop('time_limit')
                if Path(str(args.log) + '.stop').exists():
                    limits.stop('coordinator_stop')
                report_stop()

    class Proxy(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *_):
            pass

        def respond(self, status, payload, content_type='application/json'):
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            try:
                self.wfile.write(payload)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def proxy(self):
            body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            # Serialize admission and calls so concurrent requests cannot evade limits.
            with lock:
                if not limits.before(time.monotonic(), self.command, self.path, body):
                    report_stop()
                    event('blocked', method=self.command, path=self.path, reason=limits.reason)
                    self.respond(429, json.dumps({'value': {'error': 'benchmark_stopped', 'message': limits.reason + ': stop work, close session and report; do not retry or bypass proxy'}}).encode())
                    return
                started = time.time()
                connection = http.client.HTTPConnection('127.0.0.1', args.target, timeout=args.request_timeout)
                try:
                    headers = {k: v for k, v in self.headers.items() if k.lower() not in ('host', 'connection')}
                    connection.request(self.command, self.path, body=body or None, headers=headers)
                    upstream = connection.getresponse()
                    payload, status = upstream.read(), upstream.status
                    content_type = upstream.getheader('Content-Type') or 'application/octet-stream'
                except Exception as error:
                    payload = json.dumps({'value': {'error': 'proxy_error', 'message': str(error)}}).encode()
                    status, content_type = 502, 'application/json'
                    limits.stop('transport_error_outcome_unknown')
                finally:
                    connection.close()
                binary = not content_type.startswith(('application/json', 'text/', 'application/xml'))
                count = lambda text: len(encoding.encode(text, disallowed_special=())) if text else 0
                entry = {'ts': round(started, 3), 'method': self.command, 'path': self.path.split('?')[0], 'status': status,
                         'req_bytes': len(body), 'resp_bytes': len(payload),
                         'req_tokens': count(f'{self.command} {self.path}\n' + body.decode('utf-8', 'replace')),
                         'resp_tokens': count('' if binary else payload.decode('utf-8', 'replace')), 'binary': binary,
                         'ms': int((time.time() - started) * 1000)}
                log.write(json.dumps(entry) + '\n'); log.flush()
                limits.after(self.command, self.path, status, payload)
                report_stop()
                self.respond(status, payload, content_type)

        do_GET = do_POST = do_PUT = do_DELETE = proxy

    event('started', max_calls=args.max_calls, max_seconds=args.max_seconds, strict=args.strict)
    threading.Thread(target=watchdog, daemon=True).start()
    http.server.ThreadingHTTPServer(('127.0.0.1', args.listen), Proxy).serve_forever()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--listen', type=int, required=True)
    parser.add_argument('--target', type=int, required=True)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--max-calls', type=int, default=80)
    parser.add_argument('--max-seconds', type=int, default=480)
    parser.add_argument('--request-timeout', type=int, default=90)
    parser.add_argument('--strict', action='store_true')
    serve(parser.parse_args())
