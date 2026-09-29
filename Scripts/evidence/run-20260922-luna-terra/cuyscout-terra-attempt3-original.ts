/**
 * Standalone replay of the CuyWallet DEMO Sedapal flow observed on 2026-09-22.
 * Requires: tsx, webdriverio, and a locally running Appium/XCUITest server.
 * This script performs one payment. Run only in the authorized, disposable DEMO app.
 *
 * Note: the observed app went straight from btn_service_pay to the receipt; no
 * intervening summary/final-confirmation screen was exposed by CuyScout. Therefore
 * the pre-payment assertions below verify the rendered service form and inputs.
 */
import assert from 'node:assert/strict';
import { remote } from 'webdriverio';

const config = {
  host: process.env.APPIUM_HOST ?? '127.0.0.1',
  port: Number(process.env.APPIUM_PORT ?? '4723'),
  udid: process.env.IOS_UDID ?? '6D8AB10E-23C7-42AB-8BD1-CE33BC4F39EE',
  bundleId: process.env.IOS_BUNDLE_ID ?? 'com.cuywallet.app',
  email: process.env.CUYWALLET_EMAIL ?? 'demo@cuywallet.com',
  password: process.env.CUYWALLET_PASSWORD ?? 'Cuywallet2024',
  suministro: process.env.CUYWALLET_SUMINISTRO ?? '19891201',
  amount: process.env.CUYWALLET_AMOUNT ?? '12.34',
};

const timeout = 20_000;
const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function main(): Promise<void> {
  const driver = await remote({
    hostname: config.host,
    port: config.port,
    path: '/',
    capabilities: {
      platformName: 'iOS',
      'appium:automationName': 'XCUITest',
      'appium:udid': config.udid,
      'appium:bundleId': config.bundleId,
      'appium:noReset': false,
    },
  });

  const byId = (id: string) => driver.$(`~${id}`);
  const visible = async (id: string) => {
    const element = await byId(id);
    await element.waitForDisplayed({ timeout });
    return element;
  };
  const label = async (id: string) => {
    const element = await visible(id);
    return (await element.getAttribute('label')) || (await element.getText());
  };
  const assertIncludes = async (id: string, value: string) => {
    assert.ok((await label(id)).includes(value), `${id} should contain ${value}`);
  };

  try {
    await (await visible('input_email')).setValue(config.email);
    await (await visible('input_password')).setValue(config.password);
    await (await visible('btn_login')).click();
    await visible('btn_quick_pay');

    await (await visible('btn_quick_pay')).click();
    await visible('service_sedapal');
    await (await visible('service_sedapal')).click();

    // Assertions immediately before the only observed payment action.
    await assertIncludes('label_service_name', 'Sedapal');
    const suministro = await visible('input_service_suministro');
    const amount = await visible('input_service_amount');
    await suministro.setValue(config.suministro);
    await amount.setValue(config.amount);
    assert.equal(await suministro.getAttribute('value'), config.suministro);
    assert.equal(await amount.getAttribute('value'), config.amount);

    // Observed selector: this directly produced the receipt in DEMO. Never retry it.
    await (await visible('btn_service_pay')).click();

    // Receipt assertions: operation number, service, supply, and exact amount.
    await visible('label_service_result_operation');
    await assertIncludes('label_service_result_title', 'Pago exitoso');
    await assertIncludes('label_service_result_name', 'Sedapal');
    await assertIncludes('label_service_result_suministro', config.suministro);
    await assertIncludes('label_service_result_amount', `S/ ${config.amount}`);
    const operation = await label('label_service_result_operation');
    assert.match(operation, /N° Operación:\s*\S+/);
    process.stdout.write(`Payment confirmed: ${operation}; amount S/ ${config.amount}\n`);
  } finally {
    await driver.deleteSession();
  }
}

void main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
