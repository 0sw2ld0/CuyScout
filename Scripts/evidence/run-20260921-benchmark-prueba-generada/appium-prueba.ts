/**
 * CuyWallet — Pago de recibo Sedapal con Cuy Wallet
 *
 * Escenario (Gherkin):
 *   Dado que inicio sesión con el usuario demo@cuywallet.com y la contraseña Cuywallet2024
 *   Cuando pago un recibo del servicio Sedapal por el suministro 19891201 usando Cuy Wallet
 *   Entonces veo el comprobante con el número de operación y el monto pagado
 *   Y verifico el número de operación ANTES de confirmar cualquier acción irreversible
 *
 * Ejecución:
 *   npx wdio run ./wdio.conf.ts   (usando las capabilities de abajo)
 *   o bien con mocha/ts-node contra un remote() de WebdriverIO.
 *
 * Solo selectores semánticos: accessibility id (~) y predicate strings.
 * Ninguna interacción por coordenadas.
 */

import { remote, type Browser } from 'webdriverio';

const APPIUM_URL = new URL(process.env.APPIUM_URL ?? 'http://127.0.0.1:4901/');

export const capabilities = {
  platformName: 'iOS',
  'appium:automationName': 'XCUITest',
  'appium:udid': process.env.IOS_UDID ?? '937BF8FD-FEE5-4E42-AC06-5E0E7326F084',
  'appium:bundleId': 'com.cuywallet.app',
  'appium:noReset': true,
  'appium:newCommandTimeout': 120,
} as const;

const CREDENTIALS = {
  email: 'demo@cuywallet.com',
  password: 'Cuywallet2024',
};

const RECIBO = {
  servicio: 'Sedapal',
  suministro: '19891201',
  monto: '85.50',
  cuentaOrigen: 'Wallet Digital CUY',
};

/** Predicate helper: elemento cuyo `name` coincide exactamente. */
const byName = (name: string) =>
  `-ios predicate string:name == "${name.replace(/"/g, '\\"')}"`;

/** Predicate helper: elemento visible cuyo `value` contiene un texto. */
const valueContains = (text: string) =>
  `-ios predicate string:value CONTAINS "${text.replace(/"/g, '\\"')}" AND visible == 1`;

async function setField(driver: Browser, accessibilityId: string, value: string) {
  const field = await driver.$(`~${accessibilityId}`);
  await field.waitForDisplayed({ timeout: 15_000 });
  await field.click();
  await field.clearValue().catch(() => undefined); // campo puede estar vacío
  await field.setValue(value);
}

async function tap(driver: Browser, accessibilityId: string) {
  const el = await driver.$(`~${accessibilityId}`);
  await el.waitForDisplayed({ timeout: 15_000 });
  await el.click();
}

/** Lee el `value` de una etiqueta por accessibility id. */
async function readLabel(driver: Browser, accessibilityId: string): Promise<string> {
  const el = await driver.$(`~${accessibilityId}`);
  await el.waitForDisplayed({ timeout: 20_000 });
  return (await el.getAttribute('value')) ?? (await el.getText());
}

describe('CuyWallet · Pago de servicios', () => {
  let driver: Browser;

  before(async () => {
    driver = await remote({
      protocol: APPIUM_URL.protocol.replace(':', '') as 'http' | 'https',
      hostname: APPIUM_URL.hostname,
      port: Number(APPIUM_URL.port || 4723),
      path: '/',
      logLevel: 'warn',
      capabilities: {
        alwaysMatch: { ...capabilities },
        firstMatch: [{}],
      } as never,
    });
  });

  after(async () => {
    if (driver) await driver.deleteSession();
  });

  it('paga el recibo de Sedapal desde la Wallet Digital CUY y muestra el comprobante', async () => {
    // --- Dado que inicio sesión ---
    await setField(driver, 'input_email', CREDENTIALS.email);
    await setField(driver, 'input_password', CREDENTIALS.password);
    await tap(driver, 'btn_login');

    const saludo = await driver.$('~label_greeting');
    await saludo.waitForDisplayed({ timeout: 20_000 });

    // --- Cuando pago un recibo del servicio Sedapal ---
    await tap(driver, 'btn_quick_pay');

    // Pantalla "Pago de Servicios" -> tarjeta del servicio Sedapal
    const sedapal = await driver.$('~service_sedapal');
    await sedapal.waitForDisplayed({ timeout: 15_000 });
    await sedapal.click();

    // Formulario "Pagar Sedapal"
    const tituloServicio = await driver.$(valueContains(`Servicio: ${RECIBO.servicio}`));
    await tituloServicio.waitForDisplayed({ timeout: 15_000 });

    await setField(driver, 'input_service_suministro', RECIBO.suministro);

    // --- usando Cuy Wallet: cambiar la cuenta de origen ---
    await tap(driver, 'picker_service_source_account');
    const opcionWallet = await driver.$(byName(RECIBO.cuentaOrigen));
    await opcionWallet.waitForDisplayed({ timeout: 10_000 });
    await opcionWallet.click();

    await setField(driver, 'input_service_amount', RECIBO.monto);

    // Resumen previo al pago: se valida ANTES de pulsar "Pagar ahora"
    const resumenSuministro = await readLabel(driver, 'label_service_summary_suministro');
    expect(resumenSuministro).toContain(RECIBO.suministro);

    const origen = await driver.$(byName(RECIBO.cuentaOrigen));
    expect(await origen.isDisplayed()).toBe(true);

    await tap(driver, 'btn_service_pay');

    // --- Entonces veo el comprobante ---
    const titulo = await readLabel(driver, 'label_service_result_title');
    expect(titulo).toContain('Pago exitoso');

    const operacion = await readLabel(driver, 'label_service_result_operation');
    const montoPagado = await readLabel(driver, 'label_service_result_amount');
    const suministro = await readLabel(driver, 'label_service_result_suministro');
    const cuenta = await readLabel(driver, 'label_service_result_account');

    // N° de operación: formato SPnnnnnn (p. ej. SP380094)
    const nroOperacion = (operacion.match(/SP\d{4,}/) ?? [])[0];
    expect(nroOperacion).toBeDefined();
    expect(operacion).toContain('N° Operación');

    expect(montoPagado).toContain(`S/ ${RECIBO.monto}`);
    expect(suministro).toContain(RECIBO.suministro);
    expect(cuenta).toContain(RECIBO.cuentaOrigen);

    // --- Y verifico el número de operación ANTES de cualquier acción irreversible ---
    // "Compartir comprobante" es la única acción con efecto externo en esta pantalla:
    // se comprueba que existe y queda disponible, pero NO se pulsa.
    const compartir = await driver.$('~btn_service_result_share');
    expect(await compartir.isDisplayed()).toBe(true);

    // eslint-disable-next-line no-console
    console.log(`Comprobante verificado · operación=${nroOperacion} · monto=S/ ${RECIBO.monto}`);

    // Cierre limpio del flujo
    await tap(driver, 'btn_service_result_go_home');
  });
});
