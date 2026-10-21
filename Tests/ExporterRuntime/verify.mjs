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
let platform, capabilities, requests, pressedKeys, typed, hinted, version, deleted;
const androidXML = () => `<hierarchy><android.widget.Button class="android.widget.Button" resource-id="com.example.wallet:id/login" content-desc="Login" clickable="true" bounds="[0,0][200,200]" displayed="true" phase="${version}"/>
<android.widget.EditText class="android.widget.EditText" resource-id="com.example.wallet:id/email" content-desc="Email" text="${typed}" bounds="[0,200][200,300]"/>
<android.widget.Button class="android.widget.Button" resource-id="composeTag" content-desc="Bob's &quot;Pay&quot;" clickable="true" bounds="[0,300][200,400]"/>
<android.widget.Switch class="android.widget.Switch" resource-id="com.example.wallet:id/checked" checkable="true" checked="false" selected="true" bounds="[0,400][200,500]"/>
<android.widget.Switch class="android.widget.Switch" resource-id="com.example.wallet:id/unchecked" checkable="true" checked="false" selected="false" bounds="[200,400][400,500]"/>
<android.widget.Switch class="android.widget.Switch" resource-id="com.example.wallet:id/checked_only" checkable="true" checked="true" selected="false" bounds="[400,400][600,500]"/>
<android.widget.TextView class="android.widget.TextView" resource-id="com.example.wallet:id/receipt" text="DEMO-0001" bounds="[0,500][200,600]"/>
<android.widget.TextView class="android.widget.TextView" resource-id="com.example.wallet:id/literal_null" content-desc="null" text="Different text" bounds="[0,600][200,650]"/>
<android.widget.EditText class="android.widget.EditText" resource-id="com.example.wallet:id/pin-2" content-desc="Pin" bounds="[0,700][200,750]"/>
<android.widget.EditText class="android.widget.EditText" resource-id="com.example.wallet:id/hinted" hint="Test user" showing-hint="${!hinted}" text="${hinted || 'Test user'}" bounds="[0,650][200,700]"/>
<android.view.View class="android.view.View" resource-id="container" text="Container"><android.widget.TextView class="android.widget.TextView" resource-id="child" text="Child text"/></android.view.View></hierarchy>`;
const source = () => platform === 'android' ? androidXML() : `<XCUIElementTypeApplication phase="${version}"><XCUIElementTypeButton name="login" label="Login" x="0" y="0" width="200" height="200" visible="true"/></XCUIElementTypeApplication>`;
function elementID(node) { return node.getAttribute('resource-id') || 'label'; }
function contextElement(doc, url) {
    if (!url.includes('/element/')) return doc;
    const id = decodeURIComponent(url.split('/element/')[1].replace(/\/(?:attribute\/[^/]+|elements|value)$/, ''));
    const node = Array.from(doc.getElementsByTagName('*')).find(node => elementID(node) === id);
    assert.ok(node, `Unknown element ${id}`);
    return node;
}
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
            if (platform === 'android' && data.using === '-android uiautomator') {
                // Ids go through native UiAutomator (resourceIdMatches), like the real UiAutomator2 server.
                const pattern = data.value.match(/^new UiSelector\(\)\.resourceIdMatches\("(.*)"\)$/);
                assert.ok(pattern, `Unsupported UiSelector: ${data.value}`);
                const regex = new RegExp(pattern[1]);
                const doc = new DOMParser().parseFromString(androidXML(), 'text/xml');
                value = xpath.select('//*[@resource-id]', doc).filter(node => regex.test(node.getAttribute('resource-id')))
                    .map(node => ({'element-6066-11e4-a52e-4f735466cecf': elementID(node)}));
            } else if (platform === 'android') {
                assert.equal(data.using, 'xpath');
                const doc = new DOMParser().parseFromString(androidXML(), 'text/xml');
                const context = contextElement(doc, req.url);
                // UiAutomator2 scopes relative XPath to a document rooted at the selected node.
                const scope = context === doc ? doc : new DOMParser().parseFromString(context.toString(), 'text/xml');
                value = xpath.select(data.value, scope).map(node => ({'element-6066-11e4-a52e-4f735466cecf': elementID(node)}));
            } else value = [{'element-6066-11e4-a52e-4f735466cecf': data.value.includes('email') ? 'email' : 'login'}];
        } else if (req.url.endsWith('/displayed') || req.url.endsWith('/enabled')) value = true;
        else if (req.url.includes('/attribute/')) {
            const attr = req.url.split('/attribute/')[1];
            if (platform === 'android') {
                const doc = new DOMParser().parseFromString(androidXML(), 'text/xml');
                const node = contextElement(doc, req.url);
                // Real UiAutomator2 uses String(null) for absent content descriptions.
                value = node.hasAttribute(attr) ? node.getAttribute(attr) : attr === 'content-desc' ? 'null' : '';
            } else value = ({class: 'android.widget.EditText', password: 'false', text: typed, label: typed, value: typed, 'content-desc': 'Email'})[attr] ?? '';
        } else if (req.url.endsWith('/click')) version++;
        else if (req.url.endsWith('/value')) {
            if (req.url.includes('hinted/value')) hinted += data.text ?? data.value.join('');
            else typed += data.text ?? data.value.join('');
        }
        else if (req.url.endsWith('/actions')) version++;
        else if (req.url.endsWith('/appium/device/display_density')) value = 320;
        else if (req.url.endsWith('/appium/device/is_keyboard_shown')) value = false;
        else if (req.url.endsWith('/execute/sync')) {
            if (data.script === 'mobile: getDisplayDensity') value = 320;
            else if (data.script === 'mobile: isKeyboardShown') value = false;
            else if (data.script === 'mobile: pressKey') pressedKeys.push(data.args[0].keycode);
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
    ANDROID_APP_PACKAGE: '', ANDROID_APP_ACTIVITY: '', ANDROID_APP: '', CUYSCOUT_REPLAY_VALUES: '{}', CUYSCOUT_ID_FALLBACK_MS: '0'
};
try {
    const files = ['android', 'ios', 'predicate', 'missing-activity', 'redacted', 'wrong-description', 'wrong-descendant', 'wrong-selected'].map(name => join(generated, name + '.mts'));
    const compiled = await command(join(root, 'node_modules/.bin/tsc'), ['--noEmit', '--target', 'es2022', '--module', 'nodenext', '--moduleResolution', 'nodenext', '--skipLibCheck', ...files]);
    assert.equal(compiled.code, 0, compiled.output);
    for (platform of ['android', 'ios']) {
        for (const mode of ['preserve', 'restart', 'reinstall']) {
            requests = []; pressedKeys = []; typed = ''; hinted = ''; version = 0; deleted = false; capabilities = null;
            const result = await command(join(root, 'node_modules/.bin/tsx'), [join(generated, platform + '.mts')], {...environment, CUYSCOUT_REPLAY_PREPARATION: mode});
            assert.equal(result.code, 0, `${platform}/${mode}: ${result.output}`);
            assert.ok(deleted && result.output.includes('replay_completed'));
            assert.equal(capabilities.platformName, platform === 'android' ? 'Android' : 'iOS');
            assert.equal(capabilities['appium:noReset'], mode !== 'reinstall');
            assert.equal(capabilities['appium:forceAppLaunch'] ?? false, mode === 'restart');
            if (platform === 'android') {
                assert.ok(requests.some(req => decodeURIComponent(req.path).endsWith('/pin-2/click')), 'pin-1 no existe: se usa el único pin-N visible');
                assert.ok(result.output.includes('id_not_found_using_same_prefix'));
                assert.deepEqual(pressedKeys, [123, 67, 67, 67], 'eraseText: va al final del texto y borra tres veces');
                assert.equal(capabilities['appium:automationName'], 'UiAutomator2');
                assert.equal(capabilities['appium:appPackage'], 'com.example.wallet');
                assert.equal(capabilities['appium:appActivity'], '.LoginActivity');
                assert.equal(capabilities['appium:intentAction'], 'android.intent.action.MAIN');
                assert.equal(capabilities['appium:dontStopAppOnReset'], mode === 'preserve');
                assert.ok(!Object.keys(capabilities).some(key => /wda|xcode|bundleId/i.test(key)));
                const lastClick = requests.filter(req => req.path.endsWith('/click')).at(-1);
                assert.ok(decodeURIComponent(lastClick.path).endsWith('/checked/click'),
                    'Value=true must prefer the first native match, including selected=true/checked=false');
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
    for (const name of ['wrong-description', 'wrong-descendant', 'wrong-selected']) {
        requests = []; deleted = false;
        const mismatch = await command(join(root, 'node_modules/.bin/tsx'), [join(generated, name + '.mts')], environment);
        assert.notEqual(mismatch.code, 0, `assertText must reject ${name}`);
        assert.ok(deleted && mismatch.output.includes('Text mismatch'), mismatch.output);
    }
} finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
