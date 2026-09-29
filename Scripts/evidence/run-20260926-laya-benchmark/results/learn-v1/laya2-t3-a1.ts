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
const actions: Action[] = [{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"input_email"},"text":"<redacted>","type":"typeElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"input_password"},"text":"<redacted>","type":"typeElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"btn_login"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"label","value":"Ahora no"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"btn_quick_transfer"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"picker_source_account"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"label","value":"Wallet Digital CUY"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"picker_destination_account"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"label","value":"Cuenta Corriente ****1234"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"input_amount"},"text":"<redacted>","type":"typeElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"btn_transfer_continue"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"selector":{"strategy":"accessibilityIdentifier","value":"btn_confirm_transfer"},"type":"tapElement"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"},{"options":{"includeSystemAlerts":false,"interactiveOnly":false,"maxElements":200,"visibleOnly":true},"type":"accessibilityTreeWithOptions"}];
const hasFailedAttempts = false;
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
const reads = new Set(['accessibilityTree', 'accessibilityTreeWithOptions', 'accessibilityDiff',
    'findElement', 'findElements', 'elementAttribute', 'elementDisplayed', 'elementEnabled',
    'elementRect', 'elementSelected', 'elementName', 'elementProperty', 'getConfig']);
const supported = new Set(['sequence', 'tapElement', 'typeElement', 'clearElement', 'waitFor',
    'assertVisible', 'assertText', ...reads]);
function preflight(items: Action[], prefix = ''): void {
    items.forEach((action, index) => {
        const path = prefix + index;
        assert.ok(supported.has(action.type), `Unsupported replay action ${path}: ${action.type}`);
        if (action.type === 'sequence') { preflight(action.actions || [], path + '.'); return; }
        if (reads.has(action.type)) return;
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
async function find(value: string, strategy: string, timeout = 10000): Promise<WebdriverIO.Element> {
    const quoted = JSON.stringify(value);
    const locator = strategy === 'accessibilityIdentifier' ? '~' + value :
        strategy === 'label' || strategy === 'value' ? `-ios predicate string:${strategy} == ${quoted}` :
        '-ios predicate string:' + appiumPredicate(value);
    const element = await driver.$(locator);
    await element.waitForExist({ timeout, interval: 500 });
    return element.getElement();
}
async function run(items: Action[], prefix = ''): Promise<void> {
    for (const [index, action] of items.entries()) {
        const path = prefix + index;
        if (action.type === 'sequence') { await run(action.actions || [], path + '.'); continue; }
        // Observations are not assertions and never count as verification.
        if (reads.has(action.type)) continue;
        const selector = action.selector!;
        const element = await find(selector.value, selector.strategy,
            action.type === 'waitFor' ? (action.timeout ?? 10) * 1000 : 10000);
        switch (action.type) {
            case 'tapElement':
                await element.waitForEnabled({timeout: 10000, interval: 500});
                await element.click(); // exactly once; no retry on timeout/uncertain result
                break;
            case 'typeElement': await element.addValue(input(action, 'text', path)); break;
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
    assert.ok(!hasFailedAttempts, 'Recording contains failed attempts; review and record a clean flow before replay');
    const udid = required('IOS_UDID');
    const bundleId = required('IOS_BUNDLE_ID');
    preflight(actions);
    driver = await remote({
        hostname: process.env.APPIUM_HOST || '127.0.0.1', port: Number(process.env.APPIUM_PORT || 4723),
        path: '/', logLevel: 'error', connectionRetryCount: 0, connectionRetryTimeout: 60000,
        capabilities: {platformName: 'iOS', 'appium:automationName': 'XCUITest',
            'appium:udid': udid, 'appium:bundleId': bundleId, 'appium:noReset': false}
    });
    try {
        await driver.setTimeout({implicit: 0});
        await run(actions);
        console.log(JSON.stringify({status: 'replay_completed', assertions: 'recorded_only'}));
    } finally { await driver.deleteSession(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });