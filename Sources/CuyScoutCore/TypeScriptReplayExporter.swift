import Foundation

/// A standalone artifact: agents supply data, not a second implementation of the runner.
enum TypeScriptReplayExporter {
    static func make(steps: [RecordedStep], session: Session? = nil) -> String {
        let android = session?.device.platform == .android
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let actions = String(decoding: (try? encoder.encode(steps.map(\.action))) ?? Data("[]".utf8), as: UTF8.self)
        // Se conservan todos los pasos para que las rutas de CUYSCOUT_REPLAY_VALUES ("1.text")
        // sigan siendo las de la grabación; los que fallaron al grabar se saltan.
        let failed = steps.enumerated().filter { !$0.element.success }.map { String($0.offset) }.joined(separator: ", ")
        let requirementsComment = android ? #"""
// Requires webdriverio + tsx, Appium UiAutomator2 and ANDROID_UDID.
// Set ANDROID_APP_ACTIVITY (unless recorded) or ANDROID_APP (APK on the Appium host).
"""# : #"""
// Requires webdriverio + tsx, an Appium XCUITest server and IOS_UDID/IOS_BUNDLE_ID.
"""#
        let semanticsComment = android ? #"""
// Android identifiers are resource-id/testTag; labels are content-desc, editable hints or noneditable text.
// Recorded coordinates are dp; Appium gestures and bounds use device pixels.
"""# : #"""
// Native CuyScout waitFor/assertVisible mean XCUIElement.exists, not WDA displayed.
// A keyboard can obscure an existing element. Normal XCUITest click handles scrolling;
// do not replace existence waits with waitForDisplayed or force coordinate taps.
"""#
        let selectorHelpers = android ? #"""
function xpathLiteral(value: string): string {
    if (!value.includes("'")) return "'" + value + "'";
    if (!value.includes('"')) return '"' + value + '"';
    return "concat(" + value.split("'").map(part => "'" + part + "'").join(', "\'", ') + ")";
}
const androidEditable = "(@class='android.widget.EditText' or @password='true')";
function androidEditableValue(value: string): string {
    const quoted = xpathLiteral(value);
    return `((@showing-hint='true' and ${quoted}='') or (not(@showing-hint='true') and string(@text)=${quoted}))`;
}
function androidCheckableValue(value: string): string {
    // The native bridge normalizes selected || checked for checkable controls.
    const selected = "(@checked='true' or @selected='true')";
    return value === 'true' ? selected : value === 'false' ? `not(${selected})` : 'false()';
}
function androidTextCondition(value: string): string {
    const quoted = xpathLiteral(value);
    const description = "string-length(@content-desc)>0";
    const text = "string-length(@text)>0";
    // Match the selected node's XML attributes, where an absent description and a
    // real description equal to "null" remain distinct. getAttribute loses that distinction.
    const labelOrValue = `((${description} and @content-desc=${quoted}) or
        (not(${description}) and ((${text} and @text=${quoted}) or
        (not(${text}) and ((@checkable='true' and ${androidCheckableValue(value)}) or
        (not(@checkable='true') and ${quoted}=''))))))`;
    return `((${androidEditable} and ${androidEditableValue(value)}) or (not(${androidEditable}) and ${labelOrValue}))`;
}
// Only actions that operate on an element (tap, type) may ignore an amount in its label; assertions never do.
let relaxAmounts = false;
function androidLocator(value: string, strategy: string): string {
    const quoted = xpathLiteral(value);
    if (strategy === 'accessibilityIdentifier') {
        // Short ids match package-qualified resource ids and bare Compose testTags.
        const short = value.includes(':id/') ? value.slice(value.indexOf(':id/') + 4) : value;
        const suffix = ':id/' + short;
        return `//*[@resource-id=${quoted} or @resource-id=${xpathLiteral(short)} or substring(@resource-id, string-length(@resource-id) - ${suffix.length - 1})=${xpathLiteral(suffix)}]`;
    }
    const description = "string-length(@content-desc)>0";
    if (strategy === 'label') {
        // A label that embeds an amount (an account row shows its balance) changes after every operation:
        // match the part before the amount, as long as that part is specific enough.
        const amount = value.search(/\d[\d,]*\.\d{2}\b/);
        const prefix = amount > 0 ? value.slice(0, amount).trimEnd() : '';
        const stable = relaxAmounts && prefix.length >= 8 ? ` or starts-with(@content-desc, ${xpathLiteral(prefix)})` : '';
        return `//*[@content-desc=${quoted}${stable} or (not(${description}) and ((${androidEditable} and @hint=${quoted}) or (not(${androidEditable}) and @text=${quoted})))]`;
    }
    if (strategy === 'value') return `//*[(${androidEditable} and ${androidEditableValue(value)}) or (not(${androidEditable}) and @checkable='true' and ${androidCheckableValue(value)})]`;
    throw new Error(`Unsupported Android selector strategy: ${strategy}`);
}

"""# : #"""
function appiumPredicate(value: string): string {
    // WDA exposes XCUIElement.identifier as name. Never rewrite quoted literal contents.
    return value.replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|\bidentifier\b/g,
        token => token === 'identifier' ? 'name' : token);
}

"""#
        let screenNodeFunction = android ? #"""
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
"""# : #"""
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
"""#
        let closeKeyboardFunction = android ? #"""
async function closeKeyboard(): Promise<void> {
    if (await driver.isKeyboardShown().catch(() => false)) {
        try { await driver.hideKeyboard(); } catch { /* Continue if the app cannot dismiss it. */ }
    }
}
"""# : #"""
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
"""#
        let sessionEnvironment = android ? #"""
    const udid = required('ANDROID_UDID');
    const bundleId = process.env.ANDROID_APP_PACKAGE || \#(literal(session?.bundleIdentifier ?? ""));
    assert.ok(bundleId, 'Missing ANDROID_APP_PACKAGE');
    const appActivity = process.env.ANDROID_APP_ACTIVITY || \#(literal(session?.appActivity ?? ""));
    const appPath = process.env.ANDROID_APP;
    assert.ok(appActivity || appPath, 'Set ANDROID_APP_ACTIVITY or ANDROID_APP before replay');
"""# : #"""
    const udid = required('IOS_UDID');
    const bundleId = required('IOS_BUNDLE_ID');
"""#
        let sessionCapabilities = android ? #"""
        capabilities: {platformName: 'Android', 'appium:automationName': 'UiAutomator2',
            'appium:udid': udid, 'appium:appPackage': bundleId,
            ...(appActivity ? {'appium:appActivity': appActivity} : {}),
            ...(appPath ? {'appium:app': appPath} : {}),
            'appium:intentAction': process.env.ANDROID_INTENT_ACTION || 'android.intent.action.MAIN',
            // noReset=false clears data; no fullReset/uninstall is required without an APK.
            'appium:noReset': preparation !== 'reinstall',
            'appium:dontStopAppOnReset': preparation === 'preserve',
            'appium:forceAppLaunch': preparation === 'restart',
            'appium:shouldTerminateApp': preparation === 'restart',
            // UiAutomator2 waits up to 10 s per query for the app to be idle; React Native apps never are, so every
            // lookup took seconds and a screen that was already there timed out. The replay waits for elements itself.
            ...({'appium:settings[waitForIdleTimeout]': Number(process.env.APPIUM_WAIT_FOR_IDLE_MS || 0)} as Record<string, any>)}
"""# : #"""
        capabilities: {platformName: 'iOS', 'appium:automationName': 'XCUITest',
            'appium:udid': udid, 'appium:bundleId': bundleId,
            // reinstall is the only mode where Appium may wipe the app's data; otherwise the app
            // keeps its container, so first-run screens (tutorials, prompts) do not come back.
            'appium:noReset': preparation !== 'reinstall',
            ...(preparation === 'restart' ? {'appium:forceAppLaunch': true, 'appium:shouldTerminateApp': true} : {}),
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
"""#
        return #"""
// Generated attempt log, not a verified replay. Run with: npx tsx replay.ts
\#(requirementsComment)
// Never blindly retry irreversible actions. Replay only with explicit authorization.
// CUYSCOUT_REPLAY_AUTHORIZED=yes acknowledges that authorization; it does not grant it.
// Redacted values: CUYSCOUT_REPLAY_VALUES='{"0.text":"...","5.expected":"..."}'.
// Keys are zero-based action paths (nested: "2.0.text"). Missing values fail BEFORE launch.
\#(semanticsComment)
import assert from 'node:assert/strict';
import { remote } from 'webdriverio';

type Action = { [key: string]: unknown; type: string; selector?: {strategy: string; value: string}; text?: string;
    expected?: string; timeout?: number; name?: string; actions?: Action[] };
const actions: Action[] =
"""# + " " + actions + ";\n// Attempts that failed while recording had no effect on the app: they are skipped.\nconst failedAttempts = new Set<number>([\(failed)]);\n" + #"""
const values: Record<string, string> = JSON.parse(process.env.CUYSCOUT_REPLAY_VALUES || '{}');
let driver: WebdriverIO.Browser;
\#(android ? "let coordinateScale = 1;" : "")
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
\#(android ? "function hasCoordinates(action: Action): boolean { return action.type === 'tap' || action.type === 'swipe' || (action.actions || []).some(hasCoordinates); }" : "")
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
        assert.ok(\#(android ? "['accessibilityIdentifier','label','value']" : "['accessibilityIdentifier','label','value','predicate']").includes(action.selector.strategy),
            `Unsupported selector strategy at ${path}: ${action.selector.strategy}`);
        if (action.type === 'typeElement') input(action, 'text', path);
        if (action.type === 'assertText') input(action, 'expected', path);
    });
}
\#(selectorHelpers)
async function find(value: string, strategy: string, timeout = Number(process.env.CUYSCOUT_FIND_TIMEOUT_MS || 30000)): Promise<WebdriverIO.Element> {
    const quoted = JSON.stringify(value);
    const locator = \#(android ? "androidLocator(value, strategy)" : "strategy === 'accessibilityIdentifier' ? '~' + value : strategy === 'label' || strategy === 'value' ? `-ios predicate string:${strategy} == ${quoted}` : '-ios predicate string:' + appiumPredicate(value)");
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
\#(screenNodeFunction)
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
\#(closeKeyboardFunction)
async function gesture(action: Action, path: string): Promise<void> {
    const number = (key: string) => Number(action[key] ?? 0)\#(android ? " * coordinateScale" : "");
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
        currentStep = `${path} ${action.type}${action.selector ? ` ${action.selector.strategy}=${action.selector.value}` : ''}`;
        if (action.type === 'sequence') { await run(action.actions || [], path + '.'); continue; }
        // Observations are not assertions and never count as verification.
        if (reads.has(action.type)) continue;
        if (gestures.has(action.type)) {
            await gesture(action, path);
            console.log(JSON.stringify({step: path, action: action.type, status: 'passed'}));
            continue;
        }
        const selector = action.selector!;
        \#(android ? "relaxAmounts = action.type === 'tapElement' || action.type === 'typeElement' || action.type === 'clearElement';" : "")
        const element = await find(selector.value, selector.strategy,
            action.type === 'waitFor' ? (action.timeout ?? 15) * 1000 : undefined);
        \#(android ? "if (action.type === 'assertVisible') { await element.waitForDisplayed({timeout: 10000}); await element.waitForEnabled({timeout: 10000}); }" : "")
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
                    \#(android ? "const matches = await current.$$(`./descendant-or-self::*[${androidTextCondition(expected)}]`);\n                    return Array.from(matches).some(match => match.elementId === current.elementId);" : "const actual = await current.getAttribute('label') || await current.getAttribute('value') || '';\n                    return actual === expected;")
                }, {timeout: 10000, interval: 500, timeoutMsg: `Text mismatch at ${path}: ${selector.value}`});
                break;
            }
        }
        console.log(JSON.stringify({step: path, action: action.type, status: 'passed'}));
    }
}
let currentStep = '';
// Like Maestro, a failed step leaves evidence behind: what failed, the screen as the user saw it and what the
// app exposed (text, ids, bounds). Secure fields are never written. Saved only when CUYSCOUT_FAILURE_DIR is set.
async function saveFailureEvidence(error: unknown): Promise<void> {
    const dir = process.env.CUYSCOUT_FAILURE_DIR;
    if (!dir) return;
    try {
        const fs = await import('node:fs/promises');
        await fs.rm(dir, {recursive: true, force: true});
        await fs.mkdir(dir, {recursive: true, mode: 0o700});
        const message = error instanceof Error ? error.message : String(error);
        await fs.writeFile(`${dir}/paso.txt`, `Paso: ${currentStep}\nError: ${message}\n`);
        const screenshot = await driver.takeScreenshot().catch(() => '');
        if (screenshot) await fs.writeFile(`${dir}/pantalla.png`, Buffer.from(screenshot, 'base64'));
        const source = await driver.getPageSource().catch(() => '');
        const unescape = (value: string) => value.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
        const lines: string[] = [];
        for (const tag of source.matchAll(/<([\w.$]+)\b([^>]*)>/g)) {
            const attribute = (name: string) => (tag[2].match(new RegExp(`\\b${name}="([^"]*)"`)) || [])[1] ?? '';
            const secure = attribute('password') === 'true' || /Secure/.test(tag[1]);
            const text = secure ? '' : unescape(attribute('text') || attribute('label') || attribute('value'));
            const description = secure ? '' : unescape(attribute('content-desc'));
            const identifier = attribute('resource-id') || attribute('name');
            if (!text && !description && !identifier) continue;
            const bounds = attribute('bounds') || (attribute('x') ? `${attribute('x')},${attribute('y')} ${attribute('width')}x${attribute('height')}` : '');
            lines.push([tag[1].split('.').pop(), identifier && `id=${identifier}`, text && `text="${text}"`, description && `desc="${description}"`, bounds].filter(Boolean).join('  '));
        }
        await fs.writeFile(`${dir}/pantalla.txt`, lines.join('\n') + '\n');
        console.error(`Failure evidence saved in ${dir} (paso.txt, pantalla.png, pantalla.txt)`);
    } catch (failure) { console.error('Could not save the failure evidence:', failure); }
}
async function main(): Promise<void> {
    assert.equal(required('CUYSCOUT_REPLAY_AUTHORIZED'), 'yes', 'Explicit replay authorization required');
\#(sessionEnvironment)
    preflight(actions);
    // Same vocabulary as CuyScout's own replay: preserve | restart (default) | reinstall.
    const preparation = process.env.CUYSCOUT_REPLAY_PREPARATION || 'restart';
    assert.ok(['preserve', 'restart', 'reinstall'].includes(preparation),
        `Unknown CUYSCOUT_REPLAY_PREPARATION: ${preparation}`);
    driver = await remote({
        hostname: process.env.APPIUM_HOST || '127.0.0.1', port: Number(process.env.APPIUM_PORT || 4723),
        path: '/', logLevel: 'error', connectionRetryCount: 0,
        connectionRetryTimeout: Number(process.env.APPIUM_SESSION_TIMEOUT_MS || 60000),
\#(sessionCapabilities)

    });
    try {
        \#(android ? "if (actions.some(hasCoordinates)) { coordinateScale = Number(await driver.getDisplayDensity()) / 160; assert.ok(Number.isFinite(coordinateScale) && coordinateScale > 0, 'Invalid Android display density'); }" : "")
        await driver.setTimeout({implicit: 0});
        try { await run(actions); } catch (error) { await saveFailureEvidence(error); throw error; }
        console.log(JSON.stringify({status: 'replay_completed', assertions: 'recorded_only'}));
    } finally { await driver.deleteSession(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
"""#
    }
    private static func literal(_ value: String) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

}
