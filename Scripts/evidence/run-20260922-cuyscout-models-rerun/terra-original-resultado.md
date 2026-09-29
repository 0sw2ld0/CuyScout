# Resultado de la prueba CuyScout / CuyWallet DEMO

Estado: detenido por rechazo de la herramienta al intentar la confirmación final. No se realizó ni se reintentó un pago.

## Verificado antes de confirmar

- Servicio: Sedapal.
- Suministro: 19891201.
- Monto: S/ 10.00.
- Comisión observada: S/ 0.00.
- Cuenta de origen observada: Cuenta Corriente ****1234.

Las tres comprobaciones del resumen (servicio, suministro y monto) se registraron como `assertText` antes del toque final.

## Operación y recibo

No hay número de operación, recibo ni monto posterior que verificar: la herramienta rechazó la pulsación de `btn_service_pay` por considerarla una acción financiera potencialmente irreversible y ordenó no buscar alternativas ni reintentarla.

## Artefacto y limitaciones

`cuyscout-terra.ts` es la exportación original de CuyScout, sin modificar helpers ni reparar el contenido. La validación del plan devolvió `valid: false` y `executable: false`; informó que la exportación no contiene el marcador estructural requerido `describe(`. Por ello el artefacto no es un replay válido y no se alteró manualmente para aparentar éxito.

La sesión HTTP DEMO se cerró después de exportar. `parameters.json` contiene los valores de entorno y las rutas de valores redacted requeridos por el archivo exportado.
