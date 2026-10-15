"""The real-device smoke must reject reused output before contacting a gateway."""
from pathlib import Path
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest


class AndroidSmokeOutputTests(unittest.TestCase):
    def run_smoke(self, output):
        script = Path(__file__).resolve().parents[2] / 'Scripts/smoke_android_device.py'
        return subprocess.run([sys.executable, str(script), '--serial', 'unused',
            '--gateway', 'http://127.0.0.1:1', '--output', str(output),
            '--artifacts', str(output.parent / 'artifacts')], capture_output=True, text=True)

    def test_existing_evidence_is_not_mixed_with_another_run(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evidence'
            output.mkdir()
            transcript = output / 'http.jsonl'
            transcript.write_bytes(b'previous run\n')
            result = self.run_smoke(output)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('new or empty directory', result.stderr)
            self.assertNotIn('Traceback', result.stderr)
            self.assertEqual(transcript.read_bytes(), b'previous run\n')
            self.assertEqual(list(output.iterdir()), [transcript])

    def test_output_file_is_rejected_without_overwriting_it(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evidence'
            output.write_bytes(b'keep this file')
            result = self.run_smoke(output)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('new or empty directory', result.stderr)
            self.assertNotIn('Traceback', result.stderr)
            self.assertEqual(output.read_bytes(), b'keep this file')


@contextmanager
def smoke_gateway(wrong_screen=False, replay_success=True, replay_steps=12):
    """HTTP contract fixture only; this does not simulate or validate Android UI."""
    calls = []
    screens = iter(['Wrong screen' if wrong_screen else 'Iniciar sesión',
                    'Bienvenido', 'Servicio de prueba', 'Confirmar pago', 'DEMO-0001'])

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def respond(self):
            calls.append((self.command, self.path))
            body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            payload = json.loads(body) if body else {}
            content_type = 'application/json'
            if self.path == '/session':
                value = {'value': {'sessionId': 'fixture'}}
            elif self.path.endswith('/readiness?ui=false'):
                value = {'value': {'interactionReady': True}}
            elif self.path.endswith('/observe'):
                value = {'value': {'texts': [next(screens)], 'actions': []}}
            elif '/recording/appium/' in self.path or self.path.endswith('/recording/maestro.yaml'):
                value = b'export fixture'; content_type = 'text/plain'
            elif self.path.endswith('/screenshot/raw'):
                value = b'\x89PNG\r\n\x1a\n'; content_type = 'image/png'
            elif self.path == '/artifacts/fixture/replay':
                value = {'success': replay_success, 'executedSteps': replay_steps}
            elif self.path.endswith('/actions') and payload.get('type') == 'accessibilityTreeWithOptions':
                value = {'elements': [], 'count': 0}
            elif self.path in ['/session/fixture/actions', '/session/fixture/recording/stop', '/session/fixture']:
                value = {'value': None}
            else:
                self.send_error(500, 'Unexpected smoke request'); return
            data = value if isinstance(value, bytes) else json.dumps(value).encode()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = do_DELETE = respond

    server = HTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': .01}, daemon=True)
    thread.start()
    try:
        yield 'http://127.0.0.1:' + str(server.server_port), calls
    finally:
        server.shutdown(); server.server_close(); thread.join(timeout=3)


class AndroidSmokeVerificationTests(unittest.TestCase):
    def check_failure(self, message, *, wrong_screen=False, replay_success=True, replay_steps=12, system_alerts=False):
        script = Path(__file__).resolve().parents[2] / 'Scripts/smoke_android_device.py'
        for optimize in [[], ['-O']]:
            with self.subTest(optimize=optimize), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                artifacts = root / 'artifacts'
                artifacts.mkdir()
                (artifacts / 'fixture.json').write_text('{}')
                env = dict(os.environ)
                if system_alerts:
                    # This test checks HTTP verification, not Android execution.
                    adb = root / 'sdk/platform-tools/adb'
                    adb.parent.mkdir(parents=True)
                    adb.write_text('#!/bin/sh\nexit 0\n')
                    adb.chmod(0o755)
                    env['ANDROID_HOME'] = str(root / 'sdk')
                with smoke_gateway(wrong_screen, replay_success, replay_steps) as (gateway, calls):
                    command = [sys.executable, *optimize, str(script), '--serial', 'fixture',
                        '--gateway', gateway, '--output', str(root / 'output'), '--artifacts', str(artifacts),
                        '--preparations', *([] if wrong_screen or system_alerts else ['restart']),
                        *(['--system-alerts'] if system_alerts else [])]
                    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn('PASS:', result.stdout)
                self.assertIn(message, result.stderr)
                self.assertIn(('DELETE', '/session/fixture'), calls, 'Failed checks must still close their session')

    def test_wrong_screen_fails_even_with_python_optimization(self):
        self.check_failure('Expected screen text not found', wrong_screen=True)

    def test_failed_native_replay_fails_even_with_python_optimization(self):
        self.check_failure('Native replay failed', replay_success=False)

    def test_missing_permission_controls_fail_even_with_python_optimization(self):
        self.check_failure('System permission controls do not match', system_alerts=True)

    def test_empty_native_replay_is_not_a_completed_scenario(self):
        self.check_failure('Native replay failed', replay_steps=0)
