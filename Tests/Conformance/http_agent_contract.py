#!/usr/bin/env python3
"""HTTP help/action validation regression, without simulator or app actions."""
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[2]
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]

def call(method, path, body=None):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
    try:
        connection.request(method, path, body=body, headers={'Content-Type': 'application/json'})
        response = connection.getresponse()
        return response.status, json.loads(response.read())
    finally:
        connection.close()

with tempfile.TemporaryDirectory(prefix='cuyscout-http-contract-') as temp:
    server = subprocess.Popen([str(root / '.build/debug/cuyscout'), str(port)], cwd=root,
                              env=dict(os.environ, CUYSCOUT_ARTIFACT_DIR=temp, CUYSCOUT_LESSONS_FILE=temp + '/lessons.json'),
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                status, help = call('GET', '/agent-help')
                break
            except OSError:
                time.sleep(0.05)
        else:
            raise AssertionError('HTTP server did not start')
        assert status == 200 and help['mode'] == 'http'
        example = help['exampleExecuteBody']
        assert 'type' in example and 'action' not in example and 'sessionId' not in example
        for body in [json.dumps({'action': example}), '{', json.dumps({'type': 'typeElement'}), '[]']:
            status, response = call('POST', '/session/missing/actions', body)
            assert status == 400, (status, response)
            assert response['value']['error'] == 'invalid argument', response
            assert 'No action performed' in response['value']['message'], response
        status, response = call('POST', '/session/missing/actions', json.dumps(example))
        assert status == 404 and response['value']['error'] == 'invalid session id', response
        print('PASS: HTTP-specific help, raw action body, malformed/wrapped request 400, valid action reaches session validation')
    finally:
        server.terminate()
        server.wait(timeout=5)
