// Generated attempt log, not a verified replay. Run with: npx tsx replay.ts
// Requires webdriverio + tsx, Appium UiAutomator2 and ANDROID_UDID.
// Set ANDROID_APP_ACTIVITY (unless recorded) or ANDROID_APP (APK on the Appium host).
// Never blindly retry irreversible actions. Replay only with explicit authorization.
// CUYSCOUT_REPLAY_AUTHORIZED=yes acknowledges that authorization; it does not grant it.
// Redacted values: CUYSCOUT_REPLAY_VALUES='{"0.text":"...","5.expected":"..."}'.
// Keys are zero-based action paths (nested: "2.0.text"). Missing values fail BEFORE launch.
// Android identifiers are resource-id/testTag; labels are content-desc (or noneditable text).
// Recorded coordinates are dp; Appium gestures and bounds use device pixels.
import assert from 'node:assert/strict';
import { remote } from 'webdriverio';

type Action = { [key: string]: unknown; type: string; selector?: {strategy: string; value: string}; text?: string;
    expected?: string; timeout?: number; name?: string; actions?: Action[] };
const actions: Action[] = [{"options":{"hittableOnly":true,"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"username"},"text":"<redacted>","type":"typeElement"},{"selector":{"strategy":"accessibilityIdentifier","value":"login"},"type":"tapElement"},{"options":{"hittableOnly":true,"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"pay"},"type":"tapElement"},{"options":{"hittableOnly":true,"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"amount"},"text":"<redacted>","type":"typeElement"},{"selector":{"strategy":"accessibilityIdentifier","value":"continue_payment"},"type":"tapElement"},{"options":{"hittableOnly":true,"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"confirm_payment"},"type":"tapElement"},{"options":{"hittableOnly":true,"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"expected":"<redacted>","selector":{"strategy":"accessibilityIdentifier","value":"receipt"},"type":"assertText"}];
// Attempts that failed while recording had no effect on the app: they are skipped.
const failedAttempts = new Set<number>([]);
const values: Record<string, string> = JSON.parse(process.env.CUYSCOUT_REPLAY_VALUES || '{}');
let driver: WebdriverIO.Browser;
let coordinateScale = 1;
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
function hasCoordinates(action: Action): boolean { return action.type === 'tap' || action.type === 'swipe' || (action.actions || []).some(hasCoordinates); }
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
        assert.ok(['accessibilityIdentifier','label','value'].includes(action.selector.strategy),
            `Unsupported selector strategy at ${path}: ${action.selector.strategy}`);
        if (action.type === 'typeElement') input(action, 'text', path);
        if (action.type === 'assertText') input(action, 'expected', path);
    });
}
function xpathLiteral(value: string): string {
    if (!value.includes("'")) return "'" + value + "'";
    if (!value.includes('"')) return '"' + value + '"';
    return "concat(" + value.split("'").map(part => "'" + part + "'").join(', "\'", ') + ")";
}
function androidLocator(value: string, strategy: string): string {
    const quoted = xpathLiteral(value);
    if (strategy === 'accessibilityIdentifier') {
        // Short ids match package-qualified resource ids and bare Compose testTags.
        const short = value.includes(':id/') ? value.slice(value.indexOf(':id/') + 4) : value;
        const suffix = ':id/' + short;
        return `//*[@resource-id=${quoted} or @resource-id=${xpathLiteral(short)} or substring(@resource-id, string-length(@resource-id) - ${suffix.length - 1})=${xpathLiteral(suffix)}]`;
    }
    const editable = "(@class='android.widget.EditText' or @password='true')";
    const description = "string-length(@content-desc)>0";
    if (strategy === 'label') return `//*[@content-desc=${quoted} or (not(${description}) and not(${editable}) and @text=${quoted})]`;
    if (strategy === 'value') return `//*[(${editable} and @text=${quoted}) or (@checkable='true' and @checked=${quoted})]`;
    throw new Error(`Unsupported Android selector strategy: ${strategy}`);
}

async function find(value: string, strategy: string, timeout = 15000): Promise<WebdriverIO.Element> {
    const quoted = JSON.stringify(value);
    const locator = androidLocator(value, strategy);
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
    const nodes: ScreenNode[] = [];
    for (const match of source.matchAll(/<[^!?/][^>]*\bbounds="\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"[^>]*>/g)) {
        const tag = match[0];
        const attribute = (name: string) => (tag.match(new RegExp(`\\b${name}="([^"]*)"`)) || [])[1] ?? '';
        const className = attribute('class');
        const type = className.endsWith('EditText') ? 'textfield' :
            attribute('checkable') === 'true' ? 'switch' : attribute('clickable') === 'true' ? 'button' : className;
        nodes.push({type, label: '', x: Number(match[1]), y: Number(match[2]),
            width: Number(match[3]) - Number(match[1]), height: Number(match[4]) - Number(match[2]),
            visible: attribute('displayed') !== 'false'});
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
    if (await driver.isKeyboardShown().catch(() => false)) {
        try { await driver.hideKeyboard(); } catch { /* Continue if the app cannot dismiss it. */ }
    }
}
async function gesture(action: Action, path: string): Promise<void> {
    const number = (key: string) => Number(action[key] ?? 0) * coordinateScale;
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
        if (action.type === 'assertVisible') { await element.waitForDisplayed({timeout: 10000}); await element.waitForEnabled({timeout: 10000}); }
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
                    // UiAutomator2 stringifies a missing content description as the literal 'null'.
                    const description = await current.getAttribute('content-desc');
                    const actual = (await current.getAttribute('class') === 'android.widget.EditText' || await current.getAttribute('password') === 'true') ? await current.getAttribute('text') : (description && description !== 'null' ? description : '') || await current.getAttribute('text') || (await current.getAttribute('checkable') === 'true' ? await current.getAttribute('checked') : '');
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
    const udid = required('ANDROID_UDID');
    const bundleId = process.env.ANDROID_APP_PACKAGE || "com.cuycoders.cuyscout.demo";
    assert.ok(bundleId, 'Missing ANDROID_APP_PACKAGE');
    const appActivity = process.env.ANDROID_APP_ACTIVITY || ".MainActivity";
    const appPath = process.env.ANDROID_APP;
    assert.ok(appActivity || appPath, 'Set ANDROID_APP_ACTIVITY or ANDROID_APP before replay');
    preflight(actions);
    // Same vocabulary as CuyScout's own replay: preserve | restart (default) | reinstall.
    const preparation = process.env.CUYSCOUT_REPLAY_PREPARATION || 'restart';
    assert.ok(['preserve', 'restart', 'reinstall'].includes(preparation),
        `Unknown CUYSCOUT_REPLAY_PREPARATION: ${preparation}`);
    driver = await remote({
        hostname: process.env.APPIUM_HOST || '127.0.0.1', port: Number(process.env.APPIUM_PORT || 4723),
        path: '/', logLevel: 'error', connectionRetryCount: 0,
        connectionRetryTimeout: Number(process.env.APPIUM_SESSION_TIMEOUT_MS || 60000),
        capabilities: {platformName: 'Android', 'appium:automationName': 'UiAutomator2',
            'appium:udid': udid, 'appium:appPackage': bundleId,
            ...(appActivity ? {'appium:appActivity': appActivity} : {}),
            ...(appPath ? {'appium:app': appPath} : {}),
            'appium:intentAction': process.env.ANDROID_INTENT_ACTION || 'android.intent.action.MAIN',
            // noReset=false clears data; no fullReset/uninstall is required without an APK.
            'appium:noReset': preparation !== 'reinstall',
            'appium:dontStopAppOnReset': preparation === 'preserve',
            'appium:forceAppLaunch': preparation === 'restart',
            'appium:shouldTerminateApp': preparation === 'restart'}

    });
    try {
        if (actions.some(hasCoordinates)) { coordinateScale = Number(await driver.getDisplayDensity()) / 160; assert.ok(Number.isFinite(coordinateScale) && coordinateScale > 0, 'Invalid Android display density'); }
        await driver.setTimeout({implicit: 0});
        await run(actions);
        console.log(JSON.stringify({status: 'replay_completed', assertions: 'recorded_only'}));
    } finally { await driver.deleteSession(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });