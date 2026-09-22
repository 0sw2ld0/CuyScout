#!/usr/bin/env python3
"""Tool-only protocol test. Uses a fake gateway, no simulator or payments.
Run after swift build: python3 Tests/Conformance/mcp_agent_contract.py
"""
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug/cuyscout-mcp'
seen = []
observation = {
    'stateId': 'state:fixture', 'changed': True, 'context': 'NATIVE_APP', 'title': 'Fixture',
    'texts': ['amount_label: S/ 120.00'],
    'actions': [{'risk': 'medium', 'reason': 'Editable', 'action': {
        'type': 'typeElement', 'selector': {'strategy': 'accessibilityIdentifier', 'value': 'fixture_field'},
        'text': '<text>'}}],
}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_request(self):
        size = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(size)) if size else None
        seen.append((self.command, self.path, body))
        status, content_type = 200, 'application/json'
        value = {'value': None}
        if '/missing/' in self.path:
            status = 404
            value = {'value': {'error': 'invalid session id', 'message': 'Session not found'}}
        elif self.path == '/session' and self.command == 'POST':
            value = {'value': {'sessionId': 'fixture-session', 'capabilities': {'platformName': 'iOS'}}}
        elif self.path.endswith('/readiness'):
            value = {'value': {'interactionReady': True, 'blockers': []}}
        elif '/observe' in self.path:
            value = {'value': observation}
        elif self.path.endswith('/validate'):
            value = {'valid': True, 'executable': True, 'warnings': [], 'errors': []}
        elif self.path.endswith('/typescript'):
            value = 'export const fixture = true;'
            content_type = 'text/typescript'
        elif self.path == '/devices':
            value = {'value': [{'id': 'fixture-device'}]}
        elif self.path == '/status':
            value = {'value': {'ready': True}}
        payload = value.encode() if isinstance(value, str) else json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_DELETE = handle_request

def exchange(requests, env):
    # Blank lines and initialized notifications must not end the server or produce replies.
    payload = '\n' + '\n'.join(json.dumps(r) for r in requests) + '\n'
    result = subprocess.run([str(BIN)], input=payload, text=True, capture_output=True,
                            env=env, timeout=25, check=True)
    return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]

def request(i, method, params=None):
    return {'jsonrpc': '2.0', 'id': i, 'method': method, 'params': params or {}}

def tool(i, name, arguments=None):
    return request(i, 'tools/call', {'name': name, 'arguments': arguments or {}})

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory(prefix='cuyscout-mcp-test-') as temp:
        env = dict(os.environ, CUYSCOUT_GATEWAY_URL=f'http://127.0.0.1:{server.server_port}',
                   CUYSCOUT_ARTIFACT_DIR=temp, CUYSCOUT_LESSONS_FILE=f'{temp}/lessons.json')
        sid = {'sessionId': 'fixture-session'}
        copied = dict(observation['actions'][0]['action'], text='intended input')
        messages = [request(1, 'initialize'), {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            request(2, 'tools/list'), tool(3, 'cuyscout_help'),
            tool(4, 'cuyscout_create_session', {'appPath': '/fixture.app', 'deviceId': 'fixture-device'}),
            tool(5, 'cuyscout_set_timeouts', dict(sid, timeouts={'implicit': 8000})),
            tool(6, 'cuyscout_session_readiness', sid), tool(7, 'cuyscout_observe', sid),
            tool(8, 'cuyscout_execute', dict(sid, action=copied)),
            tool(9, 'cuyscout_validate_test_plan', sid), tool(10, 'cuyscout_export_appium_typescript', sid),
            tool(11, 'cuyscout_end_session', sid),
            tool(12, 'cuyscout_execute', dict(sid, action=observation['actions'][0])),
            tool(13, 'cuyscout_observe', {'sessionId': 'missing'}),
            tool(14, 'cuyscout_list_devices'), request(15, 'resources/list'),
            tool(16, 'cuyscout_record_lesson'), tool(17, 'cuyscout_observe'),
            request(18, 'resources/read', {'uri': 'cuyscout://lessons'}),
            request(19, 'prompts/get', {'name': 'cuyscout_explore_to_test'}),
            tool(20, 'cuyscout_execute', dict(sid, action=observation['actions'][0]['action'])),
        ]
        responses = exchange(messages, env)
        assert len(responses) == 20, responses
        by_id = {r['id']: r for r in responses}
        def data(i):
            result = by_id[i]['result']
            assert json.loads(result['content'][0]['text']) == result['structuredContent']
            return result['structuredContent']
        assert 'instructions' in by_id[1]['result']
        catalog = {t['name']: t for t in by_id[2]['result']['tools']}
        assert 'cuyscout_end_session' in catalog and 'cuyscout_record_lesson' not in catalog
        assert all(t['inputSchema']['type'] == 'object' for t in catalog.values())
        assert 'outputSchema' in catalog['cuyscout_observe']
        assert catalog['cuyscout_observe']['outputSchema']['properties']['texts']['items']['type'] == 'string'
        assert 'appPath' in catalog['cuyscout_create_session']['inputSchema']['properties']
        assert data(3)['mode'] == 'http-gateway'
        assert data(4)['sessionId'] == 'fixture-session'
        assert data(6)['interactionReady'] is True
        assert data(7) == observation
        assert data(8) == {'ok': True}
        assert data(9)['valid'] is True
        assert data(10)['code'] == 'export const fixture = true;'
        assert data(11) == {'ok': True}
        for i in (12, 13, 16, 17, 20):
            assert by_id[i]['result']['isError'] is True
        assert 'actions[i].action' in data(12)['error']
        assert 'invalid session id' in data(13)['error']
        assert 'placeholder' in data(20)['error']
        assert data(14)['value'][0]['id'] == 'fixture-device'
        assert by_id[15]['result']['resources'] == []
        assert by_id[18]['error'] and by_id[18]['id'] == 18
        assert 'cuyscout_end_session' in by_id[19]['result']['messages'][0]['content']['text']
        writes = [r for r in seen if r[0] == 'POST']
        assert len(writes) == 3, writes  # rejected wrapper must not reach gateway
        assert writes[0][2]['capabilities']['alwaysMatch']['appium:app'] == '/fixture.app'
        assert writes[-1][2] == copied
        assert sum(r[0] == 'DELETE' for r in seen) == 1
        # A refused connection must be a tool error with the same request id, not success.
        import socket
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            closed_port = sock.getsockname()[1]
        disconnected = exchange([tool('network', 'cuyscout_status')],
                               dict(env, CUYSCOUT_GATEWAY_URL=f'http://127.0.0.1:{closed_port}'))[0]
        assert disconnected['id'] == 'network' and disconnected['result']['isError']
        assert 'sandbox/network permissions' in disconnected['result']['structuredContent']['error']
        # Local engine remains available; installer requests must not be silently ignored.
        env.pop('CUYSCOUT_GATEWAY_URL')
        local = exchange([tool(1, 'cuyscout_help'), tool(2, 'cuyscout_create_session', {'appPath': '/fixture.app'})], env)
        assert local[0]['result']['structuredContent']['mode'] == 'local-engine-manual-bridge'
        assert local[1]['result']['isError']
    print('PASS: MCP discovery, complete tool workflow, envelope shapes, export, cleanup, errors, connectivity and mode isolation')
finally:
    server.shutdown()
    server.server_close()
    thread.join()
