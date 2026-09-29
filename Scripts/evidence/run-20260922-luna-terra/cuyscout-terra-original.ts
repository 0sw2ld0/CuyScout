/**
 * CuyWallet DEMO — observed pre-payment flow.
 *
 * This file is deliberately a partial deliverable: the proxy refused the
 * final authenticated payment action, so no receipt screen or receipt
 * selector was observed. It therefore stops after asserting the visible
 * summary instead of guessing a receipt selector or blindly retrying a pay.
 *
 * Run with: npx tsx outputs/cuyscout-terra.ts
 */
import assert from 'node:assert/strict';
import { remote, type Browser, type Element } from 'webdriverio';

const email = process.env.CUYWALLET_EMAIL ?? 'demo@cuywallet.com';
const password = process.env.CUYWALLET_PASSWORD ?? 'Cuywallet2024';
const suministro = process.env.CUYWALLET_SUMINISTRO ?? '19891201';
const amount = process.env.CUYWALLET_AMOUNT ?? '23.50';

let driver: Browser | undefined;

async function element(id: string): Promise<Element> {
  assert.ok(driver, 'Appium session is not open');
  const found = await driver.$(`~${id}`);
  await found.waitForDisplayed({ timeout: 15_000 });
  return found;
}

async function visible(id: string): Promise<string> {
  return (await element(id)).getText();
}

async function run(): Promise<void> {
  driver = await remote({
    hostname: process.env.APPIUM_HOST ?? '127.0.0.1',
    port: Number(process.env.APPIUM_PORT ?? '4723'),
    path: '/',
    capabilities: {
      platformName: 'iOS',
      'appium:automationName': 'XCUITest',
      'appium:udid': process.env.IOS_UDID,
      'appium:bundleId': process.env.IOS_BUNDLE_ID ?? 'com.cuywallet.app',
      'appium:noReset': true,
    },
  });

  await (await element('input_email')).setValue(email);
  await (await element('input_password')).setValue(password);
  await (await element('btn_login')).click();
  assert.match(await visible('label_balance_amount'), /Saldo disponible S\/\//);

  await (await element('btn_quick_pay')).click();
  assert.equal(await visible('service_sedapal'), 'Sedapal');
  await (await element('service_sedapal')).click();

  assert.equal(await visible('label_service_name'), 'Servicio: Sedapal');
  await (await element('input_service_suministro')).setValue(suministro);
  await (await element('input_service_amount')).setValue(amount);

  // Summary values were observed before the blocked final confirmation.
  assert.equal(await visible('label_service_summary_name'), 'Servicio: Sedapal');
  assert.equal(
    await visible('label_service_summary_suministro'),
    `N° Suministro: ${suministro}`,
  );
  assert.equal(await visible('label_service_summary_amount'), `Monto: S/ ${amount}`);
  assert.equal(await visible('label_service_summary_fee'), 'Comisión: S/ 0.00');

  throw new Error(
    'STOP: final payment and receipt verification were not executed. ' +
      'The observed final control is btn_service_pay; do not enable it or ' +
      'assert a receipt until it is observed in an authorized run.',
  );
}

run()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    if (driver) await driver.deleteSession();
  });
