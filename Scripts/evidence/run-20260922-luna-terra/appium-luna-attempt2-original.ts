import { remote, type Browser } from 'webdriverio';
import assert from 'node:assert/strict';

const host = process.env.APPIUM_HOST ?? '127.0.0.1';
const port = Number(process.env.APPIUM_PORT ?? '4826');
const udid = process.env.IOS_UDID ?? '037A6B09-9E33-440A-AAD0-B25BA4E77D43';
const bundleId = process.env.IOS_BUNDLE_ID ?? 'com.cuywallet.app';
const email = process.env.CUYWALLET_EMAIL ?? 'demo@cuywallet.com';
const password = process.env.CUYWALLET_PASSWORD ?? 'Cuywallet2024';
const suministro = process.env.SEDAPAL_SUMINISTRO ?? '19891201';
const amount = process.env.SEDAPAL_AMOUNT ?? '25.00';

const byId = (id: string) => `~${id}`;

async function main(): Promise<void> {
  let driver: Browser | undefined;
  try {
    driver = await remote({
      hostname: host,
      port,
      path: '/',
      logLevel: 'error',
      connectionRetryTimeout: 90_000,
      capabilities: {
        alwaysMatch: {
          platformName: 'iOS',
          'appium:automationName': 'XCUITest',
          'appium:udid': udid,
          'appium:bundleId': bundleId,
          'appium:noReset': true,
        },
      },
    });
    await driver.setTimeout({ implicit: 8_000 });

    const emailField = await driver.$(byId('input_email'));
    await emailField.waitForDisplayed();
    await emailField.setValue(email);
    await (await driver.$(byId('input_password'))).setValue(password);
    await (await driver.$(byId('btn_login'))).click();
    await (await driver.$(byId('label_greeting'))).waitForDisplayed();

    await (await driver.$(byId('btn_quick_pay'))).click();
    await (await driver.$(byId('service_sedapal'))).waitForDisplayed();
    await (await driver.$(byId('service_sedapal'))).click();

    const serviceName = await driver.$(byId('label_service_name'));
    await serviceName.waitForDisplayed();
    assert.equal(await serviceName.getText(), 'Servicio: Sedapal');

    await (await driver.$(byId('input_service_suministro'))).setValue(suministro);
    await (await driver.$(byId('input_service_amount'))).setValue(amount);

    const supplyField = await driver.$(byId('input_service_suministro'));
    const amountField = await driver.$(byId('input_service_amount'));
    assert.equal(await supplyField.getValue(), suministro);
    assert.equal(await amountField.getValue(), amount);

    const summarySupply = await driver.$(byId('label_service_summary_suministro'));
    const summaryAmount = await driver.$(byId('label_service_summary_amount'));
    await summarySupply.waitForExist();
    await summaryAmount.waitForExist();
    assert.match(await summarySupply.getText(), new RegExp(`\\b${suministro}\\b`));
    assert.match(await summaryAmount.getText(), new RegExp(`S/\\s*${amount.replace('.', '\\.')}`));

    const payButton = await driver.$(byId('btn_service_pay'));
    await payButton.waitForExist();
    assert.equal(await payButton.isEnabled(), true);
    await payButton.click();
    // The live run was blocked at this click by the safety layer, so receipt
    // selectors were not observed and are intentionally not guessed here.
  } finally {
    if (driver) await driver.deleteSession();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
