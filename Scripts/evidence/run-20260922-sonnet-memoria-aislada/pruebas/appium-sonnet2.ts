/**
 * CuyWallet - Pago de recibo Sedapal (WebdriverIO + Appium/XCUITest)
 *
 * Escenario:
 *   Dado que inicio sesión con demo@cuywallet.com / Cuywallet2024
 *   Cuando pago un recibo de Sedapal por el suministro 19891201 usando Cuy Wallet
 *   Entonces veo el comprobante con el número de operación y el monto pagado
 *   Y verifico el número de operación ANTES de confirmar cualquier acción irreversible
 *
 * Todos los selectores son semánticos: accessibility id (`~id`) o
 * -ios predicate string. No se usan coordenadas.
 *
 * Grabado manualmente contra Appium 3.2.2 (XCUITest) en http://127.0.0.1:4901,
 * udid B7C48B78-398C-4021-8362-A5EB94B40A27, bundleId com.cuywallet.app.
 */

import { remote } from "webdriverio";

const SUMINISTRO = "19891201";
const MONTO_A_PAGAR = "85.50";

describe("CuyWallet - Pago de servicio Sedapal", () => {
  let driver: WebdriverIO.Browser;

  before(async () => {
    driver = await remote({
      hostname: "127.0.0.1",
      port: 4901,
      path: "/",
      logLevel: "warn",
      capabilities: {
        platformName: "iOS",
        "appium:automationName": "XCUITest",
        "appium:udid": "B7C48B78-398C-4021-8362-A5EB94B40A27",
        "appium:bundleId": "com.cuywallet.app",
        "appium:noReset": true,
      },
    });
  });

  after(async () => {
    if (driver) {
      await driver.deleteSession();
    }
  });

  it("inicia sesión, paga el recibo Sedapal y valida el comprobante antes de confirmar", async () => {
    // --- Dado que inicio sesión ---
    const inputEmail = await driver.$("~input_email");
    await inputEmail.setValue("demo@cuywallet.com");

    const inputPassword = await driver.$("~input_password");
    await inputPassword.setValue("Cuywallet2024");

    const btnLogin = await driver.$("~btn_login");
    await btnLogin.click();

    // Confirma que el login llevó a Home ("Hola, Alex")
    const greeting = await driver.$("~label_greeting");
    await greeting.waitForDisplayed({ timeout: 8000 });

    // --- Cuando pago un recibo de Sedapal ---
    const btnQuickPay = await driver.$("~btn_quick_pay");
    await btnQuickPay.click();

    const serviceSedapal = await driver.$("~service_sedapal");
    await serviceSedapal.waitForDisplayed({ timeout: 5000 });
    await serviceSedapal.click();

    const inputSuministro = await driver.$("~input_service_suministro");
    await inputSuministro.waitForDisplayed({ timeout: 5000 });
    await inputSuministro.setValue(SUMINISTRO);

    const inputAmount = await driver.$("~input_service_amount");
    await inputAmount.setValue(MONTO_A_PAGAR);

    // Selecciona la cuenta de origen (predicate string sobre el botón,
    // ya que el texto se comparte con una etiqueta oculta del formulario)
    const pickerSourceAccount = await driver.$("~picker_service_source_account");
    await pickerSourceAccount.click();

    const cuentaCorrienteOption = await driver.$(
      '-ios predicate string:name == "Cuenta Corriente ****1234" AND type == "XCUIElementTypeButton"'
    );
    await cuentaCorrienteOption.waitForDisplayed({ timeout: 5000 });
    await cuentaCorrienteOption.click();

    // --- Verificación PRE-confirmación (antes de la acción irreversible) ---
    // El resumen del formulario debe coincidir con el objetivo antes de tocar "Pagar ahora".
    const summarySuministro = await driver.$("~label_service_summary_suministro");
    const summaryAmount = await driver.$("~label_service_summary_amount");
    const summaryName = await driver.$("~label_service_summary_name");

    expect(await summarySuministro.getText()).toContain(SUMINISTRO);
    expect(await summaryAmount.getText()).toContain(MONTO_A_PAGAR);
    expect(await summaryName.getText()).toContain("Sedapal");

    // Solo si el resumen coincide con el objetivo se confirma la acción irreversible.
    const btnServicePay = await driver.$("~btn_service_pay");
    await btnServicePay.click();

    // --- Entonces veo el comprobante con el número de operación y el monto pagado ---
    const resultTitle = await driver.$("~label_service_result_title");
    await resultTitle.waitForDisplayed({ timeout: 8000 });
    expect(await resultTitle.getText()).toBe("Pago exitoso");

    const resultOperation = await driver.$("~label_service_result_operation");
    const resultAmount = await driver.$("~label_service_result_amount");
    const resultSuministro = await driver.$("~label_service_result_suministro");
    const resultAccount = await driver.$("~label_service_result_account");

    const operationText = await resultOperation.getText();
    const amountText = await resultAmount.getText();

    expect(operationText).toMatch(/N° Operación: \S+/);
    expect(amountText).toContain(MONTO_A_PAGAR);
    expect(await resultSuministro.getText()).toContain(SUMINISTRO);
    expect(await resultAccount.getText()).toContain("Cuenta Corriente ****1234");

    console.log(`Comprobante -> ${operationText} | ${amountText}`);
  });
});
