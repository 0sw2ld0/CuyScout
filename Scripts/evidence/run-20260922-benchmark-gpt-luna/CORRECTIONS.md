# Correcciones posteriores al experimento

El archivo original `cuyscout-gpt-luna.ts` y el JSONL se conservan como evidencia.
`cuyscout-gpt-luna-fixed.ts` corrige la continuación de una sesión en el formulario
Sedapal: desenvuelve `value`, usa `actions[].action`, interpreta `texts` como cadenas,
valida resumen y comprobante por identificador, exige readiness explícito y cierra
la sesión incluso si falla. No usa el selector inventado `input_service_supply` ni
vuelve a escribir sobre campos ya completados. No reintenta el pago.

Ejecución con Node 22.22.3 o compatible:

```sh
CUYSCOUT_SESSION='<sesión activa>' CUYSCOUT_URL='http://127.0.0.1:4801' node --experimental-strip-types Scripts/evidence/run-20260922-benchmark-gpt-luna/cuyscout-gpt-luna-fixed.ts
```

Requiere el formulario con suministro 19891201, monto S/ 120.00, comisión cero y
Wallet Digital CUY, o un comprobante que coincida. Realiza el pago si está en el
formulario. El número de operación solo existe después del pago: antes se valida
el resumen. Es una continuación HTTP específica de CuyScout, no una prueba
completa de login ni un archivo WebdriverIO portable. No ejecutar el original.

Las pruebas de regresión usan respuestas simuladas y no interactúan con iOS:

```sh
node --experimental-strip-types --test Tests/Conformance/luna-continuation.test.mjs
```

## Rectificación de la medición

Los 3.880 tokens / 19 llamadas corresponden a una ejecución parcial; Sonnet completó
el escenario y el entregable en 4.999 tokens / 23 llamadas. No son resultados
comparables y no demuestran un ahorro de Luna. Incluso el cálculo de llamadas
anunciado era incorrecto: 19 frente a 23 es 17,4% menos, no 22%.
El log de 5.513 tokens / 27 llamadas incluye diagnóstico y acciones del coordinador.
No debe presentarse como ejecución autónoma de Luna ni como comparación controlada
contra Appium. El script corregido tampoco forma parte del resultado original.

El fallo de conexión del hilo aislado ocurrió mientras el proxy respondía desde
comandos con permisos ampliados. Esto apunta a aislamiento de red; no demuestra
una caída de CoreSimulatorService o del gateway. Cambiar el modelo del hilo actual
no elimina su contexto previo. Una nueva medición deberá comprobar aislamiento,
modelo, permisos y estado inicial antes de empezar a contar.
