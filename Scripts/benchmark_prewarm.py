#!/usr/bin/env python3
"""Start/close a WebDriver session without reading or navigating the app (unmeasured setup)."""
import argparse
import json
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, required=True)
parser.add_argument('--device', required=True)
args = parser.parse_args()
base = f'http://127.0.0.1:{args.port}'
caps = {'platformName': 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': args.device,
        'appium:bundleId': 'com.cuywallet.app', 'appium:noReset': True}
request = urllib.request.Request(base + '/session', data=json.dumps({'capabilities': {'alwaysMatch': caps}}).encode(),
                                 headers={'Content-Type': 'application/json'}, method='POST')
with urllib.request.urlopen(request, timeout=240) as response:
    result = json.load(response)
sid = result['value']['sessionId']
print(json.dumps({'prewarmSession': sid, 'device': args.device}), flush=True)
with urllib.request.urlopen(urllib.request.Request(base + '/session/' + sid, method='DELETE'), timeout=60) as response:
    print(json.dumps({'closed': response.status == 200}), flush=True)
