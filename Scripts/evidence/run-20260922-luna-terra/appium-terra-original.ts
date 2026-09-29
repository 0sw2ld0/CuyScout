import assert from 'node:assert/strict';
import { remote } from 'webdriverio';

const host = process.env.APPIUM_HOST ?? '127.0.0.1';
const port = Number(process.env.APPIUM_PORT ?? '4827');
const udid = process.env.IOS_UDID ?? '8A437C75-C328-44FE-8FB4-20833986352B';
const bundleId = process.env.IOS_BUNDLE_ID ?? 'com.cuywallet.app';
const email = process.env.CUYWALLET_EMAIL ?? 'demo@cuywallet.com';
const password = process.env.CUYWALLET_PASSWORD ?? 'Cuywallet2024';
const suministro = process.env.CUYWALLET_SUMINISTRO ?? '19891201';
const amount = process.env.CUYWALLET_AMOUNT ?? '27.50';

async function textOf(selector: string) {
  const element = await $(selector);
  await element.waitForExist({ timeout: 15_000 });
  return (await element.getAttribute('label')) ?? (await element.getText());
}

async function main() {
  const browser = await remote({
    hostname: host,
    port,
    path: '/',
    logLevel: 'error',
    capabilities: {
      platformName: 'iOS',
      'appium:automationName': 'XCUITest',
      'appium:udid': udid,
      'appium:bundleId': bundleId,
      'appium:noReset': true,
    },
  });

  try {
    await browser.setTimeout({ implicit: 8_000 });

    await $('~input_email').setValue(email);
    await $('~input_password').setValue(password);
    await $('~btn_login').click();
    await $('~label_greeting').waitForDisplayed({ timeout: 15_000 });

    await $('~btn_quick_pay').click();
    await $('~service_sedapal').waitForDisplayed({ timeout: 15_000 });
    await $('~service_sedapal').click();

    await $('~label_service_name').waitForDisplayed({ timeout: 15_000 });
    assert.equal(await textOf('~label_service_name'), 'Servicio: Sedapal');

    const supply = await $('~input_service_suministro');
    const paymentAmount = await $('~input_service_amount');
    await supply.setValue(suministro);
    await paymentAmount.clearValue();
    await paymentAmount.setValue(amount);
    assert.equal(await supply.getValue(), suministro);
    assert.equal(await paymentAmount.getValue(), amount);

    // The app exposes its confirmation values before the action; verify every one.
    assert.equal(await textOf('~label_service_summary_name'), 'Servicio: Sedapal');
    assert.equal(
      await textOf('~label_service_summary_suministro'),
      `N° Suministro: ${suministro}`,
    );
    assert.equal(
      await textOf('~label_service_summary_amount'),
      `Monto: S/ ${amount}`,
    );

    // Exactly one irreversible action in this session.
    await $('~btn_service_pay').click();

    await $('~label_service_result_title').waitForDisplayed({ timeout: 20_000 });
    assert.equal(await textOf('~label_service_result_title'), 'Pago exitoso');
    assert.equal(await textOf('~label_service_result_name'), 'Servicio: Sedapal');
    assert.equal(
      await textOf('~label_service_result_suministro'),
      `N° Suministro / Línea: ${suministro}`,
    );
    assert.equal(
      await textOf('~label_service_result_amount'),
      `Monto pagado: S/ ${amount}`,
    );
    assert.match(
      await textOf('~label_service_result_operation'),
      /^N° Operación: \S+$/,
    );
  } finally {
    await browser.deleteSession();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
