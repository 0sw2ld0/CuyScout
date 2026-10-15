// Execute the exact generated files with real WebdriverIO against a local W3C double.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DOMParser } from '@xmldom/xmldom';
import xpath from 'xpath';

const root = dirname(fileURLToPath(import.meta.url));
const generated = process.argv[2];
let platform, capabilities, requests, typed, version, deleted;
const androidXML = () => `<hierarchy><android.widget.Button class="android.widget.Button" resource-id="com.example.wallet:id/login" content-desc="Login" clickable="true" bounds="[0,0][200,200]" displayed="true" phase="${version}"/>
<android.widget.EditText class="android.widget.EditText" resource-id="com.example.wallet:id/email" content-desc="Email" text="${typed}" bounds="[0,200][200,300]"/>
<android.widget.Button class="android.widget.Button" resource-id="composeTag" content-desc="Bob's &quot;Pay&quot;" clickable="true" bounds="[0,300][200,400]"/>
<android.widget.Switch class="android.widget.Switch" resource-id="com.example.wallet:id/checked" checkable="true" checked="true" bounds="[0,400][200,500]"/></hierarchy>`;
const source = () => platform === 'android' ? androidXML() : `<XCUIElementTypeApplication phase="${version}"><XCUIElementTypeButton name="login" label="Login" x="0" y="0" width="200" height="200" visible="true"/></XCUIElementTypeApplication>`;
function elementID(node) { return node.getAttribute('resource-id') || 'label'; }
const server = createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    const data = body ? JSON.parse(body) : {};
    requests.push({method: req.method, path: req.url, data});
    let value = null;
    try {
        if (req.method === 'POST' && req.url === '/session') {
            capabilities = data.capabilities.alwaysMatch;
            value = {sessionId: 'fixture', capabilities};
        } else if (req.method === 'DELETE' && req.url === '/session/fixture') deleted = true;
        else if (req.url.endsWith('/timeouts') || (req.method === 'DELETE' && req.url.endsWith('/actions'))) value = null;
        else if (req.url.endsWith('/source')) value = source();
        else if (req.url.endsWith('/elements')) {
            if (platform === 'android') {
                assert.equal(data.using, 'xpath');
                const doc = new DOMParser().parseFromString(androidXML(), 'text/xml');
                value = xpath.select(data.value, doc).map(node => ({'element-6066-11e4-a52e-4f735466cecf': elementID(node)}));
            } else value = [{'element-6066-11e4-a52e-4f735466cecf': data.value.includes('email') ? 'email' : 'login'}];
        } else if (req.url.endsWith('/displayed') || req.url.endsWith('/enabled')) value = true;
        else if (req.url.includes('/attribute/')) {
            const attr = req.url.split('/attribute/')[1];
            value = ({class: 'android.widget.EditText', password: 'false', text: typed, label: typed, value: typed, 'content-desc': 'Email'})[attr] ?? '';
        } else if (req.url.endsWith('/click')) version++;
        else if (req.url.endsWith('/value')) typed += data.text ?? data.value.join('');
        else if (req.url.endsWith('/actions')) version++;
        else if (req.url.endsWith('/appium/device/display_density')) value = 320;
        else if (req.url.endsWith('/appium/device/is_keyboard_shown')) value = false;
        else if (req.url.endsWith('/execute/sync')) {
            if (data.script === 'mobile: getDisplayDensity') value = 320;
            else if (data.script === 'mobile: isKeyboardShown') value = false;
            else throw new Error(`Unexpected execute: ${data.script}`);
        } else throw new Error(`Unexpected W3C call: ${req.method} ${req.url}`);
        res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({value}));
    } catch (error) {
        res.writeHead(500, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({value: {error: 'unknown error', message: error.message}}));
    }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = String(server.address().port);
async function command(executable, args, env = {}) {
    const child = spawn(executable, args, {env: {...process.env, ...env}, stdio: ['ignore', 'pipe', 'pipe']});
    let output = ''; child.stdout.on('data', chunk => output += chunk); child.stderr.on('data', chunk => output += chunk);
    const timer = setTimeout(() => child.kill('SIGKILL'), 60000);
    try {
        const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
        return {code, output};
    } finally { clearTimeout(timer); }
}
const environment = {
    CUYSCOUT_REPLAY_AUTHORIZED: 'yes', ANDROID_UDID: 'FAKE_USB', IOS_UDID: 'FAKE_IOS', IOS_BUNDLE_ID: 'com.example.wallet',
    APPIUM_HOST: '127.0.0.1', APPIUM_PORT: port, APPIUM_SESSION_TIMEOUT_MS: '12345',
    APPIUM_XCODE_ORG_ID: 'test-team', APPIUM_PREBUILT_WDA_PATH: '/fixture/WDA.app',
    ANDROID_APP_PACKAGE: '', ANDROID_APP_ACTIVITY: '', ANDROID_APP: '', CUYSCOUT_REPLAY_VALUES: '{}'
};
try {
    const files = ['android', 'ios', 'predicate', 'missing-activity', 'redacted'].map(name => join(generated, name + '.mts'));
    const compiled = await command(join(root, 'node_modules/.bin/tsc'), ['--noEmit', '--target', 'es2022', '--module', 'nodenext', '--moduleResolution', 'nodenext', '--skipLibCheck', ...files]);
    assert.equal(compiled.code, 0, compiled.output);
    for (platform of ['android', 'ios']) {
        for (const mode of ['preserve', 'restart', 'reinstall']) {
            requests = []; typed = ''; version = 0; deleted = false; capabilities = null;
            const result = await command(join(root, 'node_modules/.bin/tsx'), [join(generated, platform + '.mts')], {...environment, CUYSCOUT_REPLAY_PREPARATION: mode});
            assert.equal(result.code, 0, `${platform}/${mode}: ${result.output}`);
            assert.ok(deleted && result.output.includes('replay_completed'));
            assert.equal(capabilities.platformName, platform === 'android' ? 'Android' : 'iOS');
            assert.equal(capabilities['appium:noReset'], mode !== 'reinstall');
            assert.equal(capabilities['appium:forceAppLaunch'] ?? false, mode === 'restart');
            if (platform === 'android') {
                assert.equal(capabilities['appium:automationName'], 'UiAutomator2');
                assert.equal(capabilities['appium:appPackage'], 'com.example.wallet');
                assert.equal(capabilities['appium:appActivity'], '.LoginActivity');
                assert.equal(capabilities['appium:intentAction'], 'android.intent.action.MAIN');
                assert.equal(capabilities['appium:dontStopAppOnReset'], mode === 'preserve');
                assert.ok(!Object.keys(capabilities).some(key => /wda|xcode|bundleId/i.test(key)));
            } else {
                assert.equal(capabilities['appium:xcodeOrgId'], 'test-team');
                assert.equal(capabilities['appium:usePreinstalledWDA'], true);
            }
            const moves = requests.filter(req => req.path.endsWith('/actions') && req.method === 'POST')
                .flatMap(req => req.data.actions.flatMap(input => input.actions)).filter(action => action.type === 'pointerMove');
            const scale = platform === 'android' ? 2 : 1;
            assert.deepEqual(moves.map(({x, y}) => [x, y]), [[10*scale,20*scale],[10*scale,20*scale],[20*scale,40*scale]]);
            console.log(`PASS ${platform}/${mode}: real WDIO, selectors, text assertions, dp/pixel gestures and teardown`);
        }
    }
    platform = 'android';
    for (const [file, error] of [['predicate', 'Unsupported selector strategy'], ['missing-activity', 'Set ANDROID_APP_ACTIVITY'], ['redacted', 'Set CUYSCOUT_REPLAY_VALUES']]) {
        requests = [];
        const result = await command(join(root, 'node_modules/.bin/tsx'), [join(generated, file + '.mts')], environment);
        assert.notEqual(result.code, 0); assert.ok(result.output.includes(error), result.output);
        assert.equal(requests.length, 0, 'Invalid input must fail before contacting Appium');
    }
} finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
