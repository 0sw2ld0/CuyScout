import assert from 'node:assert/strict';
import { remote, type Browser } from 'webdriverio';

const host = process.env.APPIUM_HOST || '127.0.0.1';
const port = Number(process.env.APPIUM_PORT || '4723');
const udid = process.env.IOS_UDID || 'DEMO-UDID';
const bundleId = process.env.IOS_BUNDLE_ID || 'com.cuywallet.app';
const email = process.env.CUYWALLET_EMAIL || 'demo@cuywallet.com';
const password = process.env.CUYWALLET_PASSWORD || 'Cuywallet2024';
const supply = process.env.CUYWALLET_SUPPLY || '19891201';
const amount = process.env.CUYWALLET_AMOUNT || '25.00';

type Driver = Browser;

async function element(driver: Driver, id: string) {
  const item = await driver.$(`~${id}`);
  await item.waitForDisplayed({ timeout: 10_000 });
  return item;
}

async function textOf(driver: Driver, id: string): Promise<string> {
  return (await element(driver, id)).getText();
}

async function main(): Promise<void> {
  let driver: Driver | undefined;
  try {
    driver = await remote({
      hostname: host,
      port,
      path: '/',
      capabilities: {
        platformName: 'iOS',
        'appium:automationName': 'XCUITest',
        'appium:udid': udid,
        'appium:bundleId': bundleId,
        'appium:noReset': false,
      },
    });

    await (await element(driver, 'input_email')).setValue(email);
    await (await element(driver, 'input_password')).setValue(password);
    await (await element(driver, 'btn_login')).click();
    await element(driver, 'btn_quick_pay');

    await (await element(driver, 'btn_quick_pay')).click();
    await (await element(driver, 'service_sedapal')).click();
    await (await element(driver, 'input_service_suministro')).setValue(supply);
    await (await element(driver, 'input_service_amount')).setValue(amount);

    assert.equal(await textOf(driver, 'label_service_summary_name'), 'Servicio: Sedapal');
    assert.equal(await textOf(driver, 'label_service_summary_suministro'), `N° Suministro: ${supply}`);
    assert.equal(await textOf(driver, 'label_service_summary_amount'), `Monto: S/ ${amount}`);

    await (await element(driver, 'btn_service_pay')).click();
    assert.equal(await textOf(driver, 'label_service_result_title'), 'Pago exitoso');
    assert.equal(await textOf(driver, 'label_service_result_name'), 'Servicio: Sedapal');
    assert.equal(await textOf(driver, 'label_service_result_suministro'), `N° Suministro / Línea: ${supply}`);
    assert.equal(await textOf(driver, 'label_service_result_amount'), `Monto pagado: S/ ${amount}`);
    const operation = await textOf(driver, 'label_service_result_operation');
    assert.match(operation, /^N° Operación: .+/);
    console.log(JSON.stringify({ ok: true, operation, amount, supply }));
  } finally {
    if (driver) await driver.deleteSession();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
