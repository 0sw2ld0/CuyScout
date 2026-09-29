import assert from 'node:assert/strict';
import { remote, type Browser } from 'webdriverio';

const host = process.env.APPIUM_HOST ?? '127.0.0.1';
const port = Number(process.env.APPIUM_PORT ?? '4826');
const udid = process.env.IOS_UDID ?? '95A044AA-3146-4EAB-A2EB-F63F87433718';
const bundleId = process.env.IOS_BUNDLE_ID ?? 'com.cuywallet.app';
const email = process.env.CUYWALLET_EMAIL ?? 'demo@cuywallet.com';
const password = process.env.CUYWALLET_PASSWORD ?? 'Cuywallet2024';
const suministro = process.env.SEDAPAL_SUMINISTRO ?? '19891201';
const amount = process.env.SEDAPAL_AMOUNT ?? '12.34';

const byId = (id: string) => `~${id}`;

async function setValue(browser: Browser, selector: string, value: string) {
  const element = await browser.$(byId(selector));
  await element.waitForDisplayed({ timeout: 15_000 });
  await element.setValue(value);
}

async function click(browser: Browser, selector: string) {
  const element = await browser.$(byId(selector));
  await element.waitForDisplayed({ timeout: 15_000 });
  await element.click();
}

async function value(browser: Browser, selector: string): Promise<string> {
  const element = await browser.$(byId(selector));
  await element.waitForExist({ timeout: 15_000 });
  return String(await element.getAttribute('value'));
}

let browser: Browser | undefined;
try {
  browser = await remote({
    hostname: host,
    port,
    path: '/',
    logLevel: 'warn',
    capabilities: {
      platformName: 'iOS',
      'appium:automationName': 'XCUITest',
      'appium:udid': udid,
      'appium:bundleId': bundleId,
      'appium:noReset': true,
    },
  });
  await browser.setTimeout({ implicit: 8_000 });

  await setValue(browser, 'input_email', email);
  await setValue(browser, 'input_password', password);
  await click(browser, 'btn_login');

  await click(browser, 'btn_quick_pay');
  await click(browser, 'service_sedapal');
  await setValue(browser, 'input_service_suministro', suministro);
  await setValue(browser, 'input_service_amount', amount);

  assert.equal(await value(browser, 'label_service_summary_name'), 'Servicio: Sedapal');
  assert.equal(await value(browser, 'label_service_summary_suministro'), `N° Suministro: ${suministro}`);
  assert.equal(await value(browser, 'label_service_summary_amount'), `Monto: S/ ${amount}`);

  const payButton = await browser.$(byId('btn_service_pay'));
  assert.equal(await payButton.isEnabled(), true);

  // The live run was stopped here because the environment blocked the financial side effect.
  // Keep this guard explicit so a clean reproduction cannot pay accidentally.
  if (process.env.CONFIRM_PAYMENT !== '1') {
    throw new Error('Payment not executed: set CONFIRM_PAYMENT=1 after confirming the demo payment policy.');
  }

  await payButton.click();
  throw new Error('Payment confirmation/receipt selectors were not observed in the allowed run; do not infer them.');
} finally {
  if (browser) await browser.deleteSession();
}

