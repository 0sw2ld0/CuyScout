/**
 * Pago de recibo Sedapal con Cuy Wallet — prueba generada desde la grabación de CuyScout
 * y completada a mano (valores reales y aserciones del comprobante).
 *
 * Escenario:
 *   Dado que inicio sesión con el usuario demo@cuywallet.com y la contraseña Cuywallet2024
 *   Cuando pago un recibo del servicio Sedapal por el suministro 19891201 usando Cuy Wallet
 *   Entonces veo el comprobante con el número de operación y el monto pagado
 *   Y verifico el número de operación ANTES de confirmar cualquier acción irreversible
 *
 * Todos los selectores son semánticos (accessibilityIdentifier, o label cuando el
 * control no expone identificador). No hay coordenadas.
 *
 * Ejecutar:
 *   IOS_UDID=... IOS_BUNDLE_ID=com.cuywallet.app npx wdio run wdio.conf.ts
 */
import { remote } from 'webdriverio';
import { expect } from '@wdio/globals';

let driver: WebdriverIO.Browser;

const CREDENCIALES = {
    email: process.env.CUYWALLET_EMAIL || 'demo@cuywallet.com',
    password: process.env.CUYWALLET_PASSWORD || 'Cuywallet2024'
};

const RECIBO = {
    servicio: 'Sedapal',
    suministro: '19891201',
    monto: '120.00',
    origen: 'Wallet Digital CUY'
};

async function find(value: string, strategy: string): Promise<WebdriverIO.Element> {
    switch (strategy) {
        case 'accessibilityIdentifier': return driver.$('~' + value);
        case 'label': return driver.$(`//*[@label="${value}"]`);
        case 'value': return driver.$(`//*[@value="${value}"]`);
        case 'predicate': return driver.$('-ios predicate string:' + value);
        default: return driver.$(value);
    }
}

/** Texto accesible de un elemento identificado por accessibilityIdentifier. */
async function textoDe(id: string): Promise<string> {
    const el = await find(id, 'accessibilityIdentifier');
    await el.waitForDisplayed({ timeout: 8000 });
    return (await el.getAttribute('label')) || (await el.getText());
}

describe('Pago de servicios — Sedapal con Cuy Wallet', () => {
    before(async () => {
        driver = await remote({
            hostname: process.env.APPIUM_HOST || '127.0.0.1',
            port: Number(process.env.APPIUM_PORT || 4723),
            path: '/',
            capabilities: {
                platformName: 'iOS',
                'appium:automationName': 'XCUITest',
                'appium:deviceName': process.env.IOS_DEVICE_NAME || 'iPhone 17 Pro',
                'appium:udid': process.env.IOS_UDID,
                'appium:bundleId': process.env.IOS_BUNDLE_ID || 'com.cuywallet.app',
                'appium:noReset': true
            }
        });
        await driver.setTimeout({ implicit: 8000 });
    });

    after(async () => { if (driver) await driver.deleteSession(); });

    it('paga el recibo y muestra el comprobante con número de operación y monto', async () => {
        // --- Dado: inicio de sesión ---
        await (await find('input_email', 'accessibilityIdentifier')).setValue(CREDENCIALES.email);
        await (await find('input_password', 'accessibilityIdentifier')).setValue(CREDENCIALES.password);
        await (await find('btn_login', 'accessibilityIdentifier')).click();

        await expect(await find('label_greeting', 'accessibilityIdentifier')).toBeDisplayed();

        // --- Cuando: pago de servicio Sedapal ---
        await (await find('btn_quick_pay', 'accessibilityIdentifier')).click();
        await (await find('service_sedapal', 'accessibilityIdentifier')).click();

        await (await find('input_service_suministro', 'accessibilityIdentifier'))
            .setValue(RECIBO.suministro);

        // Origen: la wallet digital CUY, no la cuenta corriente por defecto.
        await (await find('picker_service_source_account', 'accessibilityIdentifier')).click();
        await (await find(RECIBO.origen, 'label')).click();

        await (await find('input_service_amount', 'accessibilityIdentifier'))
            .setValue(RECIBO.monto);

        // --- Verificación ANTES de la acción irreversible (confirmar el pago) ---
        const resumenServicio = await textoDe('label_service_summary_name');
        const resumenSuministro = await textoDe('label_service_summary_suministro');
        const resumenMonto = await textoDe('label_service_summary_amount');
        const resumenComision = await textoDe('label_service_summary_fee');

        expect(resumenServicio).toContain(RECIBO.servicio);
        expect(resumenSuministro).toContain(RECIBO.suministro);
        expect(resumenMonto).toContain(`S/ ${RECIBO.monto}`);
        expect(resumenComision).toContain('S/ 0.00');
        await expect(await find('picker_service_source_account', 'accessibilityIdentifier'))
            .toHaveText(expect.stringContaining(RECIBO.origen));

        // Solo con el resumen verificado se confirma el pago.
        await (await find('btn_service_pay', 'accessibilityIdentifier')).click();

        // --- Entonces: comprobante ---
        const titulo = await textoDe('label_service_result_title');
        expect(titulo).toContain('Pago exitoso');

        const operacionTexto = await textoDe('label_service_result_operation');
        const operacion = operacionTexto.match(/SP\d{6}/)?.[0];
        expect(operacion, `sin número de operación en "${operacionTexto}"`).toBeDefined();
        console.log(`N° Operación: ${operacion}`);

        expect(await textoDe('label_service_result_amount')).toContain(`S/ ${RECIBO.monto}`);
        expect(await textoDe('label_service_result_name')).toContain(RECIBO.servicio);
        expect(await textoDe('label_service_result_suministro')).toContain(RECIBO.suministro);
        expect(await textoDe('label_service_result_account')).toContain(RECIBO.origen);

        await expect(await find('btn_service_result_go_home', 'accessibilityIdentifier'))
            .toBeDisplayed();
    });
});
