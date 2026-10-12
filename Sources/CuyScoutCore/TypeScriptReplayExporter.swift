import Foundation

/// A standalone artifact: agents supply data, not a second implementation of the runner.
enum TypeScriptReplayExporter {
    static func make(steps: [RecordedStep]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let actions = String(decoding: (try? encoder.encode(steps.map(\.action))) ?? Data("[]".utf8), as: UTF8.self)
        // Se conservan todos los pasos para que las rutas de CUYSCOUT_REPLAY_VALUES ("1.text")
        // sigan siendo las de la grabación; los que fallaron al grabar se saltan.
        let failed = steps.enumerated().filter { !$0.element.success }.map { String($0.offset) }.joined(separator: ", ")
        return #"""
// Generated attempt log, not a verified replay. Run with: npx tsx replay.ts
// Requires webdriverio + tsx, an Appium XCUITest server and IOS_UDID/IOS_BUNDLE_ID.
// Never blindly retry irreversible actions. Replay only with explicit authorization.
// CUYSCOUT_REPLAY_AUTHORIZED=yes acknowledges that authorization; it does not grant it.
// Redacted values: CUYSCOUT_REPLAY_VALUES='{"0.text":"...","5.expected":"..."}'.
// Keys are zero-based action paths (nested: "2.0.text"). Missing values fail BEFORE launch.
// Native CuyScout waitFor/assertVisible mean XCUIElement.exists, not WDA displayed.
// A keyboard can obscure an existing element. Normal XCUITest click handles scrolling;
// do not replace existence waits with waitForDisplayed or force coordinate taps.
import assert from 'node:assert/strict';
import { remote } from 'webdriverio';

type Action = { [key: string]: unknown; type: string; selector?: {strategy: string; value: string}; text?: string;
    expected?: string; timeout?: number; name?: string; actions?: Action[] };
const actions: Action[] =
"""# + " " + actions + ";\n// Attempts that failed while recording had no effect on the app: they are skipped.\nconst failedAttempts = new Set<number>([\(failed)]);\n" + #"""
const values: Record<string, string> = JSON.parse(process.env.CUYSCOUT_REPLAY_VALUES || '{}');
let driver: WebdriverIO.Browser;
function required(name: string): string {
    const value = process.env[name];
    assert.ok(value, `Missing ${name}`);
    return value;
}
function input(action: Action, field: 'text' | 'expected', path: string): string {
    const value = values[`${path}.${field}`] ?? action[field];
    assert.ok(typeof value === 'string' && value !== '<redacted>' && value !== '<text>',
        `Set CUYSCOUT_REPLAY_VALUES["${path}.${field}"] before replay`);
    return value;
}
// Observations (screen reads, screenshots) change nothing in the app: they are skipped.
const reads = new Set(['accessibilityTree', 'accessibilityTreeWithOptions', 'accessibilityDiff',
    'findElement', 'findElements', 'elementAttribute', 'elementDisplayed', 'elementEnabled',
    'elementRect', 'elementSelected', 'elementName', 'elementProperty', 'getConfig',
    'screenshot', 'elementScreenshot', 'alertText', 'activeElement', 'listApps', 'getClipboard']);
// Coordinate gestures carry no selector: they are less stable but still replayable.
const gestures = new Set(['tap', 'swipe', 'type']);
const supported = new Set(['sequence', 'tapElement', 'typeElement', 'clearElement', 'waitFor',
    'assertVisible', 'assertText', ...reads, ...gestures]);
function preflight(items: Action[], prefix = ''): void {
    items.forEach((action, index) => {
        if (prefix === '' && failedAttempts.has(index)) return;
        const path = prefix + index;
        assert.ok(supported.has(action.type), `Unsupported replay action ${path}: ${action.type}`);
        if (action.type === 'sequence') { preflight(action.actions || [], path + '.'); return; }
        if (reads.has(action.type)) return;
        if (action.type === 'type') { input(action, 'text', path); return; }
        if (gestures.has(action.type)) {
            assert.ok(typeof action.x === 'number' || typeof action.fromX === 'number', `Missing coordinates at ${path}`);
            return;
        }
        assert.ok(action.selector?.value, `Missing selector at ${path}`);
        assert.ok(['accessibilityIdentifier','label','value','predicate'].includes(action.selector.strategy),
            `Unsupported selector strategy at ${path}: ${action.selector.strategy}`);
        if (action.type === 'typeElement') input(action, 'text', path);
        if (action.type === 'assertText') input(action, 'expected', path);
    });
}
function appiumPredicate(value: string): string {
    // WDA exposes XCUIElement.identifier as name. Never rewrite quoted literal contents.
    return value.replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|\bidentifier\b/g,
        token => token === 'identifier' ? 'name' : token);
}
async function find(value: string, strategy: string, timeout = 15000): Promise<WebdriverIO.Element> {
    const quoted = JSON.stringify(value);
    const locator = strategy === 'accessibilityIdentifier' ? '~' + value :
        strategy === 'label' || strategy === 'value' ? `-ios predicate string:${strategy} == ${quoted}` :
        '-ios predicate string:' + appiumPredicate(value);
    // Like CuyScout: several matches (a button and its own label) are fine; prefer the
    // first one that is displayed. webdriverio's strict \$() would reject them.
    let matches: WebdriverIO.Element[] = [];
    await driver.waitUntil(async () => {
        matches = Array.from(await driver.$$(locator));
        return matches.length > 0;
    }, { timeout, interval: 500, timeoutMsg: `Element not found: ${locator}` });
    for (const candidate of matches.slice(0, 5)) {
        if (await candidate.isDisplayed().catch(() => false)) return candidate;
    }
    return matches[0];
}
// Screen elements from WDA's page source (points, like the recording).
type ScreenNode = {type: string; label: string; x: number; y: number; width: number; height: number; visible: boolean};
function screenNodes(source: string): ScreenNode[] {
    const unescape = (text: string) => text.replace(/&quot;/g, '"').replace(/&apos;/g, "'")
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
    const nodes: ScreenNode[] = [];
    for (const match of source.matchAll(/<XCUIElementType(\w+)\b([^>]*)>/g)) {
        const attribute = (name: string) => (match[2].match(new RegExp(`\\b${name}="([^"]*)"`)) || [])[1] ?? '';
        nodes.push({type: match[1], label: unescape(attribute('label') || attribute('name')),
            x: Number(attribute('x')) || 0, y: Number(attribute('y')) || 0,
            width: Number(attribute('width')) || 0, height: Number(attribute('height')) || 0,
            visible: attribute('visible') !== 'false'});
    }
    return nodes;
}
// Same control types CuyScout counts as interactive.
const interactiveTypes = ['button', 'textfield', 'securetextfield', 'textview', 'searchfield', 'link', 'cell',
    'switch', 'slider', 'stepper', 'toggle', 'checkbox', 'menuitem', 'picker', 'tab'];
function controlUnder(source: string, x: number, y: number): boolean {
    return screenNodes(source).some(node => node.visible && interactiveTypes.some(type => node.type.toLowerCase().includes(type))
        && x >= node.x && x <= node.x + node.width && y >= node.y && y <= node.y + node.height);
}
// Like CuyScout: before a coordinate tap, wait (up to 15 s) until the screen stops changing
// with a control under the point, or the tap lands while the next screen is still loading.
async function waitForSettledScreen(timeout = 15000, point?: {x: number; y: number}): Promise<string> {
    let previous = '';
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
        const source = await driver.getPageSource().catch(() => '');
        if (source && source === previous && (!point || controlUnder(source, point.x, point.y))) return source;
        previous = source;
        await driver.pause(500);
    }
    return previous;
}
async function screenChanges(before: string, timeout: number): Promise<boolean> {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
        await driver.pause(300);
        const source = await driver.getPageSource().catch(() => before);
        if (source !== before) return true;
    }
    return false;
}
async function tapAt(x: number, y: number): Promise<void> {
    await driver.action('pointer', {parameters: {pointerType: 'touch'}})
        .move({x: Math.round(x), y: Math.round(y)}).down().pause(80).up().perform();
}
// Like CuyScout's runner: after typing the keyboard is closed. Appium's hideKeyboard often
// fails ("Did not know how to dismiss the keyboard"), so the same fallbacks are tried: the
// Done/OK button above the keyboard, a return key that only confirms, the screen title (no
// action) and a drag down over the content. Never Return/Go/Send: it may submit the form.
async function closeKeyboard(): Promise<void> {
    const shown = () => driver.isKeyboardShown().catch(() => false);
    if (!(await shown())) return;
    try { await driver.hideKeyboard(); } catch {}
    if (!(await shown())) return;
    const nodes = screenNodes(await driver.getPageSource().catch(() => ''));
    const keyboard = nodes.find(node => node.type === 'Keyboard');
    if (!keyboard) return;
    const closeWords = new Set(['done', 'listo', 'ok', 'aceptar', 'hecho', 'cerrar', 'close', 'ocultar teclado', 'hide keyboard', 'dismiss']);
    const linkHints = ['?', 'olvid', 'aquí', 'aqui', 'ver ', 'más', 'mas ', 'términos', 'terminos', 'here', 'forgot', 'more'];
    const buttons = nodes.filter(node => node.type === 'Button' && closeWords.has(node.label.toLowerCase().trim()));
    const attempts: ScreenNode[] = [];
    const toolbar = buttons.find(node => node.y + node.height <= keyboard.y + 2 && node.y >= keyboard.y - 80);
    if (toolbar) attempts.push(toolbar);
    const key = buttons.find(node => node.y < keyboard.y + keyboard.height && node.y + node.height > keyboard.y);
    if (key) attempts.push(key);
    const title = nodes.filter(node => node.type === 'StaticText' && node.visible && node.label !== ''
            && !linkHints.some(hint => node.label.toLowerCase().includes(hint))
            && node.y > 50 && node.y + node.height < keyboard.y - 20 && node.height < 80)
        .sort((a, b) => a.y - b.y)[0];
    if (title) attempts.push(title);
    for (const target of attempts) {
        await tapAt(target.x + target.width / 2, target.y + target.height / 2);
        await driver.pause(400);
        if (!(await shown())) return;
    }
    const {width, height} = await driver.getWindowSize();
    const startY = Math.max(height * 0.2, keyboard.y - 120);
    await driver.action('pointer', {parameters: {pointerType: 'touch'}})
        .move({x: Math.round(width / 2), y: Math.round(startY)}).down()
        .move({x: Math.round(width / 2), y: Math.round(startY + 100), duration: 300}).up().perform();
    await driver.pause(400);
}
async function gesture(action: Action, path: string): Promise<void> {
    const number = (key: string) => Number(action[key] ?? 0);
    if (action.type === 'type') { await driver.keys(input(action, 'text', path).split('')); await closeKeyboard(); return; }
    if (action.type === 'tap') {
        const point = {x: number('x'), y: number('y')};
        const before = await waitForSettledScreen(15000, point);
        await tapAt(point.x, point.y);
        // Like Maestro's retryTapIfNoChange: a tap that changed nothing (it landed during an
        // animation) is repeated once. The app needs a moment to react (right after the tap
        // WDA still shows the old screen), so it is repeated only if nothing changed in 3 s.
        if (before && !(await screenChanges(before, 3000))) {
            await tapAt(point.x, point.y);
            console.log(JSON.stringify({step: path, action: 'tap', note: 'repeated: the screen did not change'}));
        }
        return;
    }
    await waitForSettledScreen();
    await driver.action('pointer', {parameters: {pointerType: 'touch'}})
        .move({x: Math.round(number('fromX')), y: Math.round(number('fromY'))}).down()
        .move({x: Math.round(number('toX')), y: Math.round(number('toY')), duration: Math.round((Number(action.duration ?? 0.3)) * 1000)})
        .up().perform();
}
async function run(items: Action[], prefix = ''): Promise<void> {
    for (const [index, action] of items.entries()) {
        if (prefix === '' && failedAttempts.has(index)) continue;
        const path = prefix + index;
        if (action.type === 'sequence') { await run(action.actions || [], path + '.'); continue; }
        // Observations are not assertions and never count as verification.
        if (reads.has(action.type)) continue;
        if (gestures.has(action.type)) {
            await gesture(action, path);
            console.log(JSON.stringify({step: path, action: action.type, status: 'passed'}));
            continue;
        }
        const selector = action.selector!;
        const element = await find(selector.value, selector.strategy,
            action.type === 'waitFor' ? (action.timeout ?? 15) * 1000 : 15000);
        switch (action.type) {
            case 'tapElement':
                await element.waitForEnabled({timeout: 10000, interval: 500});
                await element.click(); // exactly once; no retry on timeout/uncertain result
                break;
            case 'typeElement':
                await element.addValue(input(action, 'text', path));
                // After entering data the keyboard is closed; if the app can't, continue.
                await closeKeyboard();
                break;
            case 'clearElement': await element.clearValue(); break;
            case 'assertText': {
                const expected = input(action, 'expected', path);
                await driver.waitUntil(async () => {
                    const current = await find(selector.value, selector.strategy);
                    const actual = await current.getAttribute('label') || await current.getAttribute('value') || '';
                    return actual === expected;
                }, {timeout: 10000, interval: 500, timeoutMsg: `Text mismatch at ${path}: ${selector.value}`});
                break;
            }
        }
        console.log(JSON.stringify({step: path, action: action.type, status: 'passed'}));
    }
}
async function main(): Promise<void> {
    assert.equal(required('CUYSCOUT_REPLAY_AUTHORIZED'), 'yes', 'Explicit replay authorization required');
    const udid = required('IOS_UDID');
    const bundleId = required('IOS_BUNDLE_ID');
    preflight(actions);
    driver = await remote({
        hostname: process.env.APPIUM_HOST || '127.0.0.1', port: Number(process.env.APPIUM_PORT || 4723),
        path: '/', logLevel: 'error', connectionRetryCount: 0,
        connectionRetryTimeout: Number(process.env.APPIUM_SESSION_TIMEOUT_MS || 60000),
        capabilities: {platformName: 'iOS', 'appium:automationName': 'XCUITest',
            'appium:udid': udid, 'appium:bundleId': bundleId, 'appium:noReset': false,
            // The first session builds and launches WebDriverAgent: Appium itself waits only
            // 60 s for it by default, independently of connectionRetryTimeout.
            'appium:wdaLaunchTimeout': Number(process.env.APPIUM_WDA_LAUNCH_TIMEOUT_MS || 60000),
            // Without it a failed WebDriverAgent build only says "xcodebuild failed with code 65":
            // the real cause (signing, destination, Xcode version) goes to the Appium log.
            'appium:showXcodeLog': process.env.APPIUM_SHOW_XCODE_LOG !== '0',
            // Simulator: a prebuilt WebDriverAgent is installed as is, without xcodebuild.
            ...(process.env.APPIUM_PREBUILT_WDA_PATH ? {'appium:usePreinstalledWDA': true,
                'appium:prebuiltWDAPath': process.env.APPIUM_PREBUILT_WDA_PATH} : {}),
            // Physical iPhone: Appium signs its own WebDriverAgent with this team.
            ...(process.env.APPIUM_XCODE_ORG_ID ? {'appium:xcodeOrgId': process.env.APPIUM_XCODE_ORG_ID,
                'appium:xcodeSigningId': 'Apple Development', 'appium:allowProvisioningDeviceRegistration': true,
                'appium:updatedWDABundleId': process.env.APPIUM_WDA_BUNDLE_ID || 'com.cuyscout.WebDriverAgentRunner'} : {})}
    });
    try {
        await driver.setTimeout({implicit: 0});
        await run(actions);
        console.log(JSON.stringify({status: 'replay_completed', assertions: 'recorded_only'}));
    } finally { await driver.deleteSession(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
"""#
    }
}
