"""Project/stdio MCP integration, invoked by test_android_sessions with isolated tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def exercise_project(gateway, request, base, env, root, serial, driver):
    project = root / ('project with spaces ' + driver)
    apk = root / 'Wallet $literal; fixture.apk'
    apk.touch()
    runenv = dict(env, CUYSCOUT_URL=base)
    binary = str(Path(gateway).resolve())
    mcp_binary = str(Path(binary).with_name('cuyscout-mcp'))
    subprocess.run([binary, 'init', str(project), '--platform', 'android', '--app-path', str(apk), '--application-id', 'com.example.wallet', '--app-activity', '.LoginActivity', '--driver-id', driver, '--device-id', serial, '--mcp'], env=runenv, check=True, capture_output=True, text=True)
    subprocess.run([binary, 'init', str(project), '--platform', 'android', '--app-path', str(apk), '--application-id', 'com.example.wallet'], env=runenv, check=True, capture_output=True, text=True)
    config = json.loads((project / '.cuyscout-project.json').read_text())
    assert config['platform'] == 'android' and not config['simulator']
    assert config['android']['driverId'] == driver and config['android']['deviceId'] == serial and config['android']['activity'] == '.LoginActivity'
    assert config['android']['apk'] == str(apk) and config['android']['applicationId'] == 'com.example.wallet'
    guide = (project / 'AGENTS.md').read_text()
    assert 'app Android' in guide and 'observe → decidir → execute → observe' in guide
    tools = root / 'tools'; tools.mkdir(exist_ok=True)
    xcrun = tools / 'xcrun'
    xcrun.write_text('#!/bin/sh\necho "unexpected xcrun call" >&2\nexit 99\n'); xcrun.chmod(0o755)
    runenv['PATH'] = str(tools) + os.pathsep + runenv['PATH']
    opened = subprocess.run(['bash', str(project / 'scripts/open-session.sh')], env=runenv, text=True, capture_output=True, timeout=60)
    assert opened.returncode == 0, opened.stderr
    sid = opened.stdout.strip()
    session = request(base, 'GET', '/session/' + sid)['value']
    assert session['capabilities']['appium:driverId'] == driver
    request(base, 'POST', f'/session/{sid}/actions', {'type':'assertVisible', 'selector':{'strategy':'accessibilityIdentifier','value':'login'}})
    # Fragmentos: se guardan desde la grabación, se listan y se ejecutan (aquí ya se cumple la comprobación: se omite).
    import urllib.error
    assert request(base, 'GET', f'/session/{sid}/fragments')['value'] == []
    request(base, 'POST', f'/session/{sid}/actions', {'type':'tapElement', 'selector':{'strategy':'accessibilityIdentifier','value':'login'}})
    saved = request(base, 'POST', f'/session/{sid}/fragments', {'name':'qa', 'exitCheck':{'strategy':'accessibilityIdentifier','value':'login'}})['value']
    assert saved['steps'] == 1 and saved['path'] == 'fragments/qa.android.json', saved
    assert (project / saved['path']).exists()
    assert [item['name'] for item in request(base, 'GET', f'/session/{sid}/fragments')['value']] == ['qa']
    ran = request(base, 'POST', f'/session/{sid}/fragments/qa/run', {})['value']
    assert ran['ok'] and ran['skipped'] and ran['stepsRun'] == 0, ran
    try:
        request(base, 'POST', f'/session/{sid}/fragments/nada/run', {})
        raise AssertionError('un fragmento inexistente debía rechazarse')
    except urllib.error.HTTPError as error:
        assert error.code == 400, error.code
    # La grabación debe terminar en un paso bueno para poder reproducirse.
    request(base, 'POST', f'/session/{sid}/actions', {'type':'assertVisible', 'selector':{'strategy':'accessibilityIdentifier','value':'login'}})
    request(base, 'DELETE', '/session/' + sid)
    artifact = root / 'artifacts' / (sid + '.json')
    destination = project / 'output/qa.cuyscout.json'
    shutil.copyfile(artifact, destination)
    code = subprocess.run([binary, 'export-appium', str(destination), 'ts'], env=runenv, text=True, capture_output=True, check=True).stdout
    (project / 'output/qa.ts').write_text(code)
    replay = subprocess.run(['bash', str(project / 'scripts/replay-cuyscout.sh'), 'qa'], env=runenv, capture_output=True, text=True, timeout=60)
    assert replay.returncode == 0, replay.stdout + replay.stderr

    # Real stdio MCP process -> real HTTP gateway -> injected adb/bridge double.
    def mcp(method, params, local=False):
        mcpenv = dict(runenv, CUYSCOUT_GATEWAY_URL='' if local else base)
        call = {'jsonrpc':'2.0','id':1,'method':method,'params':params}
        child = subprocess.run([mcp_binary], input=json.dumps(call)+'\n', env=mcpenv, capture_output=True, text=True, timeout=30)
        assert child.returncode == 0, child.stderr
        result = json.loads(child.stdout)['result']
        assert not result.get('isError'), result
        return result
    listed = mcp('tools/list', {})
    create = next(tool for tool in listed['tools'] if tool['name'] == 'cuyscout_create_session')
    props = create['inputSchema']['properties']
    assert props['platformName']['enum'] == ['iOS', 'Android'] and 'android-device' in props['driverId']['examples']
    args = {'platformName':'Android','driverId':driver,'deviceId':serial,'bundleIdentifier':'com.example.wallet','appActivity':'.LoginActivity','projectDir':str(project)}
    created = mcp('tools/call', {'name':'cuyscout_create_session','arguments':args})['structuredContent']
    mcp_sid = created['sessionId']
    assert created['capabilities']['platformName'] == 'Android'
    mcp('tools/call', {'name':'cuyscout_end_session','arguments':{'sessionId':mcp_sid}})
    local = mcp('tools/call', {'name':'cuyscout_create_session','arguments':args}, local=True)['structuredContent']
    assert local['driverID'] == driver and local['device']['platform'] == 'android' and local['appActivity'] == '.LoginActivity'

    # Dispatch through generated Appium script; generated TS itself has separate WDIO tests.
    appium = tools / 'appium'
    appium.write_text('#!' + sys.executable + '\n' + '''import http.server,json,sys,traceback,signal
# Background fixtures must remain terminable even if the CI parent ignores SIGTERM.
signal.signal(signal.SIGTERM, signal.SIG_DFL)
if sys.argv[1:3] == ['driver','list']:
    print('uiautomator2'); sys.exit()
port = int(sys.argv[sys.argv.index('--port')+1])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"value":{"ready":true}}')
    def log_message(self,*args): pass
try:
    http.server.HTTPServer(('127.0.0.1',port),Handler).serve_forever()
except Exception:
    from pathlib import Path
    Path(sys.argv[sys.argv.index('--log')+1]).write_text(traceback.format_exc())
    raise
'''); appium.chmod(0o755)
    npx = tools / 'npx'
    capture = root / ('appium-env-' + driver + '.json')
    npx.write_text('#!' + sys.executable + '\n' + '''import json,os
from pathlib import Path
Path(os.environ['CUYSCOUT_FAKE_APPIUM_ENV']).write_text(json.dumps({key:os.environ.get(key) for key in ['ANDROID_UDID','ANDROID_APP_PACKAGE','ANDROID_APP_ACTIVITY','ANDROID_APP','CUYSCOUT_REPLAY_PREPARATION']}))
'''); npx.chmod(0o755)
    runner = root / 'appium runner'
    for package in ['webdriverio', 'tsx']: (runner / 'node_modules' / package).mkdir(parents=True, exist_ok=True)
    runenv.update(CUYSCOUT_APPIUM_RUNNER_DIR=str(runner), CUYSCOUT_FAKE_APPIUM_ENV=str(capture))
    check = subprocess.run(['bash', str(project / 'scripts/replay-appium.sh'), '--check'], env=runenv, text=True, capture_output=True)
    assert check.returncode == 0 and 'UiAutomator2' in check.stdout and 'XCUITest' not in check.stdout, check.stdout + check.stderr
    for mode in ['preserve','restart','reinstall']:
        runenv['CUYSCOUT_REPLAY_PREPARATION'] = mode
        print(f'Checking Appium dispatch {driver}/{mode}', flush=True)
        try:
            # The generated script allows 30s for server readiness, plus prerequisite/setup time.
            replay = subprocess.run(['bash', str(project / 'scripts/replay-appium.sh'), 'qa'], env=runenv, capture_output=True, text=True, timeout=90)
        except subprocess.TimeoutExpired as error:
            raise AssertionError(f'{driver}/{mode} timed out: stdout={error.stdout!r} stderr={error.stderr!r}') from error
        appium_log = project / 'output/qa.appium.log'
        assert replay.returncode == 0, replay.stdout + replay.stderr + (appium_log.read_text() if appium_log.exists() else '')
        values = json.loads(capture.read_text())
        assert values == {'ANDROID_UDID':serial,'ANDROID_APP_PACKAGE':'com.example.wallet','ANDROID_APP_ACTIVITY':'.LoginActivity','ANDROID_APP':str(apk),'CUYSCOUT_REPLAY_PREPARATION':mode}, values
        assert 'unexpected xcrun' not in replay.stderr
    print(f'PASS {driver}: CLI init, generated open/native/Appium scripts and gateway/local MCP')
