import { remote } from 'webdriverio';
import { expect } from '@wdio/globals';

let driver: WebdriverIO.Browser;

async function find(value: string, strategy: string): Promise<WebdriverIO.Element> {
    switch (strategy) {
        case 'accessibilityIdentifier': return driver.$('~' + value);
        case 'label': return driver.$(`//*[@label="${value}"]`);
        case 'value': return driver.$(`//*[@value="${value}"]`);
        case 'predicate': return driver.$('-ios predicate string:' + value);
        default: return driver.$(value);
    }
}

describe('CuyScout exploration', () => {
    before(async () => {
        driver = await remote({
            hostname: process.env.APPIUM_HOST || '127.0.0.1',
            port: Number(process.env.APPIUM_PORT || 4723),
            path: '/',
            capabilities: {
                platformName: 'iOS',
                'appium:automationName': 'XCUITest',
                'appium:deviceName': process.env.IOS_DEVICE_NAME || 'iPhone Simulator',
                'appium:udid': process.env.IOS_UDID,
                'appium:bundleId': process.env.IOS_BUNDLE_ID,
                'appium:noReset': true
            }
        });
    });

    after(async () => { if (driver) await driver.deleteSession(); });

    it('replays the CuyScout exploration', async () => {
        // Acción registrada no traducida automáticamente: accessibilityTreeWithOptions(CuyScoutCore.AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: Optional(200)))
        // Acción registrada no traducida automáticamente: accessibilityTreeWithOptions(CuyScoutCore.AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: Optional(200)))
        await (await find('input_email', 'accessibilityIdentifier')).setValue(process.env.CUYWALLET_EMAIL || 'demo@cuywallet.com');
        await (await find('input_password', 'accessibilityIdentifier')).setValue(process.env.CUYWALLET_PASSWORD || 'Cuywallet2024');
        await (await find('btn_login', 'accessibilityIdentifier')).click();
        // Acción registrada no traducida automáticamente: accessibilityTreeWithOptions(CuyScoutCore.AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: Optional(200)))
        await (await find('btn_quick_pay', 'accessibilityIdentifier')).click();
        // Acción registrada no traducida automáticamente: accessibilityTreeWithOptions(CuyScoutCore.AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: Optional(200)))
        await (await find('service_sedapal', 'accessibilityIdentifier')).click();
        // Acción registrada no traducida automáticamente: accessibilityTreeWithOptions(CuyScoutCore.AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: Optional(200)))
        await (await find('input_service_suministro', 'accessibilityIdentifier')).setValue('19891201');
        // Acción registrada no traducida automáticamente: accessibilityTreeWithOptions(CuyScoutCore.AccessibilityOptions(visibleOnly: true, interactiveOnly: false, maxElements: Optional(200)))
        await (await find('input_service_amount', 'accessibilityIdentifier')).setValue('120.00');

        // Verificar el resumen ANTES de confirmar la acción irreversible (el pago)
        const summaryAmount = await (await find('label_service_summary_amount', 'accessibilityIdentifier')).getText();
        expect(summaryAmount).toContain('120.00');
        const summarySuministro = await (await find('label_service_summary_suministro', 'accessibilityIdentifier')).getText();
        expect(summarySuministro).toContain('19891201');

        await (await find('btn_service_pay', 'accessibilityIdentifier')).click();

        // Comprobante: capturar y verificar número de operación y monto pagado
        const operationLabel = await (await find('label_service_result_operation', 'accessibilityIdentifier')).getText();
        expect(operationLabel).toMatch(/N° Operación: \S+/);
        const amountLabel = await (await find('label_service_result_amount', 'accessibilityIdentifier')).getText();
        expect(amountLabel).toContain('S/ 120.00');
        const suministroLabel = await (await find('label_service_result_suministro', 'accessibilityIdentifier')).getText();
        expect(suministroLabel).toContain('19891201');
    });
});