import { remote } from 'webdriverio';
import { expect } from '@wdio/globals';

let driver: WebdriverIO.Browser;

describe('CuyWallet - pagar recibo Sedapal', () => {
    before(async () => {
        driver = await remote({
            hostname: process.env.APPIUM_HOST || '127.0.0.1',
            port: Number(process.env.APPIUM_PORT || 4901),
            path: '/',
            capabilities: {
                platformName: 'iOS',
                'appium:automationName': 'XCUITest',
                'appium:udid': process.env.IOS_UDID || '89D87458-5CD9-4963-BB90-11B60F942E8E',
                'appium:bundleId': process.env.IOS_BUNDLE_ID || 'com.cuywallet.app',
                'appium:noReset': true
            }
        });
    });

    after(async () => {
        if (driver) await driver.deleteSession();
    });

    it('inicia sesión y paga el recibo de Sedapal del suministro 19891201', async () => {
        // Dado que inicio sesión con el usuario demo y su contraseña
        const emailField = await driver.$('~input_email');
        await emailField.clearValue();
        await emailField.setValue(process.env.CUYWALLET_EMAIL || 'demo@cuywallet.com');

        const passwordField = await driver.$('~input_password');
        await passwordField.setValue(process.env.CUYWALLET_PASSWORD || 'Cuywallet2024');

        await (await driver.$('~btn_login')).click();

        // Home: confirmar que el saludo aparece antes de continuar
        const greeting = await driver.$('~label_greeting');
        await greeting.waitForDisplayed({ timeout: 8000 });

        // Cuando pago un recibo del servicio Sedapal por el suministro 19891201
        await (await driver.$('~btn_quick_pay')).click();
        await (await driver.$('~service_sedapal')).click();

        const suministroField = await driver.$('~input_service_suministro');
        await suministroField.waitForDisplayed({ timeout: 8000 });
        await suministroField.setValue('19891201');

        const amountField = await driver.$('~input_service_amount');
        await amountField.clearValue();
        await amountField.setValue('85.50');

        // El botón de pago solo se habilita cuando el formulario es válido
        const payButton = await driver.$('~btn_service_pay');
        await driver.waitUntil(async () => await payButton.isEnabled(), {
            timeout: 5000,
            timeoutMsg: 'btn_service_pay no se habilitó tras completar el formulario'
        });
        await payButton.click();

        // Entonces veo el comprobante con el número de operación y el monto pagado
        const operationLabel = await driver.$('~label_service_result_operation');
        await operationLabel.waitForDisplayed({ timeout: 8000 });
        const operationText = await operationLabel.getText();

        const amountLabel = await driver.$('~label_service_result_amount');
        const amountText = await amountLabel.getText();

        const suministroLabel = await driver.$('~label_service_result_suministro');
        const suministroText = await suministroLabel.getText();

        // Y verifico el número de operación y los datos del comprobante ANTES
        // de dar por válida cualquier acción irreversible (el pago ya ejecutado)
        expect(operationText).toMatch(/N° Operación: \S+/);
        expect(amountText).toContain('S/ 85.50');
        expect(suministroText).toContain('19891201');

        const serviceLabel = await driver.$('~label_service_result_name');
        expect(await serviceLabel.getText()).toContain('Sedapal');
    });
});
