#!/usr/bin/env python3
"""Real-device smoke against the offline :smokeapp fixture (never uses adb doubles).

Start a gateway with CUYSCOUT_AUTORECORD=true and CUYSCOUT_ARTIFACT_DIR set first.
The SDK, runner APKs and demo APK must be built and the target online/authorized.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--gateway', default='http://127.0.0.1:18765')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--preparations', nargs='*', choices=['restart', 'reinstall', 'preserve'],
                        default=['restart', 'reinstall', 'preserve'])
    parser.add_argument('--system-alerts', action='store_true',
                        help='Also verify the API 33+ notification permission dialog')
    args = parser.parse_args()
    if args.output.exists() and (not args.output.is_dir() or any(args.output.iterdir())):
        parser.error('--output must be a new or empty directory; keep each run separate')
    root = Path(__file__).resolve().parent.parent
    apk = root / 'Runner/AndroidRunner/smokeapp/build/outputs/apk/debug/smokeapp-debug.apk'
    package = 'com.cuycoders.cuyscout.demo'
    args.output.mkdir(parents=True, exist_ok=True)
    transcript = args.output / 'http.jsonl'

    def request(method, route, body=None):
        headers = {'Content-Type': 'application/json'}
        if os.environ.get('CUYSCOUT_TOKEN'):
            headers['Authorization'] = 'Bearer ' + os.environ['CUYSCOUT_TOKEN']
        req = urllib.request.Request(args.gateway + route, method=method, headers=headers,
                                     data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=240) as response:
                data = response.read()
                request.raw = data
                content_type = response.headers.get('Content-Type', '')
                result = json.loads(data) if 'json' in content_type else data
        except urllib.error.HTTPError as error:
            raise RuntimeError(error.read().decode()) from error
        # All values originate in this public, fictitious fixture. Never store headers.
        if not isinstance(result, bytes):
            with transcript.open('a') as log:
                log.write(json.dumps({'method': method, 'route': route, 'body': body, 'response': result}, ensure_ascii=False) + '\n')
        return result

    sid = None
    try:
        created = request('POST', '/session', {'capabilities': {'alwaysMatch': {
            'platformName': 'Android', 'appium:udid': args.serial,
            'appium:appPackage': package, 'appium:appActivity': '.MainActivity',
            'appium:app': str(apk), 'appium:fullReset': True}}})['value']
        sid = created['sessionId']
        path = '/session/' + sid
        for _ in range(120):
            if request('GET', path + '/readiness?ui=false')['value']['interactionReady']:
                break
            time.sleep(.5)
        else:
            raise RuntimeError('Runner did not become ready')

        def observe(name, expected):
            result = request('GET', path + '/observe')
            (args.output / (name + '-observe.json')).write_bytes(request.raw)
            assert any(expected in text for text in result['value']['texts']), result
            return result['value']

        def action(kind, identifier, **extra):
            return request('POST', path + '/actions', {'type': kind,
                'selector': {'strategy': 'accessibilityIdentifier', 'value': identifier}, **extra})

        observe('01-login', 'Iniciar sesión')
        action('typeElement', 'username', text='demo')
        action('tapElement', 'login')
        observe('02-home', 'Bienvenido')
        action('tapElement', 'pay')
        observe('03-payment', 'Servicio de prueba')
        action('typeElement', 'amount', text='12.50')
        action('tapElement', 'continue_payment')
        observe('04-confirm', 'Confirmar pago')
        action('tapElement', 'confirm_payment')
        observe('05-receipt', 'DEMO-0001')
        action('assertText', 'receipt', expected='Pago completado · Operación DEMO-0001 · S/ 12.50')
        # Stop recording before diagnostic captures so replays contain only the scenario.
        request('POST', path + '/recording/stop', {})
        for route, filename in [('appium/typescript', 'replay.ts'), ('maestro.yaml', 'maestro.yaml')]:
            (args.output / filename).write_bytes(request('GET', path + '/recording/' + route))
        (args.output / 'receipt.png').write_bytes(request('GET', path + '/screenshot/raw'))
        if args.system_alerts:
            adb = str(Path(os.environ['ANDROID_HOME']) / 'platform-tools/adb')
            for command in [['am', 'force-stop', package], ['am', 'start', '-W', '-n', package + '/.MainActivity']]:
                subprocess.run([adb, '-s', args.serial, 'shell'] + command, check=True, capture_output=True)
            action('typeElement', 'username', text='demo')
            action('tapElement', 'login')
            action('tapElement', 'notifications')
            for include in [False, True]:
                tree = request('POST', path + '/actions', {'type': 'accessibilityTreeWithOptions',
                    'options': {'visibleOnly': True, 'interactiveOnly': False, 'hittableOnly': False,
                                'includeSystemAlerts': include, 'maxElements': 200}})
                (args.output / ('permission-' + str(include).lower() + '.json')).write_text(json.dumps(tree, ensure_ascii=False))
                identifiers = {element['identifier'] for element in tree['elements']}
                assert ('permission_allow_button' in identifiers) == include, tree
                assert ('permission_deny_button' in identifiers) == include, tree
            (args.output / 'permission.png').write_bytes(request('GET', path + '/screenshot/raw'))
            action('tapElement', 'permission_deny_button')
        request('DELETE', path)
        sid = None
        artifact = args.artifacts / (created['sessionId'] + '.json')
        (args.output / 'scenario.cuyscout.json').write_bytes(artifact.read_bytes())
        results = {}
        values = {'1.text': 'demo', '6.text': '12.50',
                  '11.expected': 'Pago completado · Operación DEMO-0001 · S/ 12.50'}
        (args.output / 'replay-values.json').write_text(json.dumps(values, ensure_ascii=False))
        for mode in args.preparations:
            if mode == 'preserve':
                # Establish the recorded starting screen; preserve itself must not reset it.
                adb = str(Path(os.environ['ANDROID_HOME']) / 'platform-tools/adb')
                subprocess.run([adb, '-s', args.serial, 'shell', 'am', 'force-stop', package], check=True, capture_output=True)
                subprocess.run([adb, '-s', args.serial, 'shell', 'am', 'start', '-W', '-n', package + '/.MainActivity'], check=True, capture_output=True)
            result = request('POST', '/artifacts/' + created['sessionId'] + '/replay',
                             {'preparation': mode, 'deviceID': args.serial, 'variables': values})
            results[mode] = result
            (args.output / 'native-replay.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
            assert result['success'], result
        print('PASS: real Android login → payment → receipt; native replays: ' + ', '.join(args.preparations))
    finally:
        if sid is not None:
            request('DELETE', '/session/' + sid)


if __name__ == '__main__':
    main()
