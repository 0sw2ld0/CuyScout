# Resultados Sedapal — Luna y Terra

Actualización posterior: [el exportador corregido de CuyScout completó una reproducción limpia](../run-20260922-cuyscout-replay-fixed-export2/RESULTADOS.md).
Es una validación de producto, no una repetición de estas corridas de modelos; sus resultados históricos no se sustituyen.

22 de septiembre de 2026. Modelos `gpt-5.6-luna` y `gpt-5.6-terra`, razonamiento `medium`. Base `e2c1b30`; reparaciones `043f12d` y `51c3bb6`. Las cuatro celdas exploratorias terminaron. Tres realizaron un pago DEMO; una quedó bloqueada por el entorno. **No equivale a cuatro pruebas correctas ni a cuatro archivos reproducibles.**

## Últimas corridas

| Modelo / herramienta | Intento | Llamadas HTTP | Tokens de tráfico | Escenario observado | Original / reproducción |
|---|---:|---:|---:|---|---|
| Luna / CuyScout | 3 | 25 | 6 740 | Resumen y comprobante verificados; S/ 25.00, SP501127 | Compila; replay falla al esperar el resumen visible |
| Luna / Appium | 2 | 24 | 51 094 | Resumen S/ 25.00; pago bloqueado otra vez por seguridad del entorno | Parcial; no compila por capabilities |
| Terra / CuyScout | 3 | 20 | 4 599 | Pago S/ 12.34, SP602301; **no observó el resumen tras llenar los campos** | Compila; replay cortado por límite de llamadas esperando el botón visible |
| Terra / Appium | 1 | 34 | 114 549 | Resumen y comprobante verificados; S/ 27.50, SP201817 | Replay falla: `$` no definido |

No se calculan ventajas de tokens entre una corrida completa, otra bloqueada y otra que omitió una verificación. Luna sí logró operar CuyScout sin `AGENT-GUIDE.md`, pero su original no superó la reproducción. No se puede prometer que cualquier ejecución futura tendrá éxito.

Los controles estaban fuera de los modelos: 80 llamadas, 480 segundos desde la primera petición y hasta 90 segundos en curso; cortes por repetición y error de servidor, con DELETE permitido para cerrar. Ninguna última corrida agotó estos límites. No se permitió continuar tras el HTTP 500 del primer intento CuyScout. Todos los intentos y sus controles se conservan.

### Incidencias que cambian la interpretación

- **Luna/Appium:** `exec_command` rechazó el pago antes de transmitir HTTP, incluso después de que el usuario renovara la autorización tras conocer el riesgo. No fue un error de Appium y no se eludió. Su archivo puede pulsar el botón pero no contiene comprobaciones del recibo; no se considera completo ni se ejecutó para sortear el rechazo.
- **Terra/CuyScout:** interpretó `btn_service_pay` como una transición al resumen, pero el resumen aparece en el mismo formulario después de escribir los datos. No hizo un `observe` entre llenar el monto y pulsar ese botón. La ausencia de una pantalla intermedia no demuestra ausencia del resumen; las otras corridas sí lo observaron. Esta omisión es del agente y se conserva como incumplimiento, no como defecto de CuyScout.
- Esa petición de Terra usó `curl --max-time 30` y agotó 30.006 s. El proxy recibió HTTP 200 del servidor a los 31.582 s; la siguiente observación confirmó el comprobante. **No reintentó el pago.** No hubo HTTP 500 ni una respuesta de error de CuyScout que obligara a reparar y reiniciar el producto.
- Los planes de las dos corridas nuevas de CuyScout devolvieron `valid:true`, `executable:false` por acciones observacionales. Esto no demuestra que los scripts Appium exportados o adaptados funcionen; su reproducción se verificó aparte.

## Referencia histórica: Sonnet, segunda prueba

| Modelo / herramienta | Llamadas | Tokens petición | Tokens respuesta | Total | Latencia HTTP acumulada |
|---|---:|---:|---:|---:|---:|
| Sonnet / CuyScout | 23 | 915 | 4 084 | 4 999 | 50.587 s |
| Sonnet / Appium | 34 | 1 231 | 98 567 | 99 798 | 32.763 s |
| Luna / CuyScout | 25 | 930 | 5 810 | 6 740 | 24.786 s |
| Luna / Appium | 24 | 1 186 | 49 908 | 51 094 | 27.497 s |
| Terra / CuyScout | 20 | 811 | 3 788 | 4 599 | 55.522 s |
| Terra / Appium | 34 | 1 405 | 113 144 | 114 549 | 41.483 s |

Las cifras se recalcularon desde los logs. Sonnet completó ambos pagos según su evidencia histórica; sus originales no se reprodujeron de nuevo en esta matriz. Se conservan intactos los resultados anteriores.

Esto cuenta línea de petición/cuerpo y cuerpo de respuesta con `cl100k_base`: **tráfico HTTP, no consumo total del modelo ni coste económico**. La latencia acumulada excluye razonamiento y redacción. Duración de las tareas: Luna/CuyScout 363.023 s, Luna/Appium 433.906 s, Terra/CuyScout 327.648 s y Terra/Appium 337.670 s. Las auditorías posteriores no se suman.

La nueva evaluación usa ayuda HTTP en lugar de una guía del repositorio, otra versión de CuyScout y límites externos. Es comparable en medición y objetivo, no una réplica experimental idéntica.

## Historia completa de intentos

| Celda / intento anterior | Llamadas | Tokens | Resultado y tratamiento |
|---|---:|---:|---|
| Luna/CuyScout 1 | 8 | 1 783 | Ayuda HTTP ambigua y decodificación 500: detenido, reparado e invalidado |
| Luna/CuyScout 2 | 3 | 1 062 | El agente ignoró una sesión creada y volvió a crearla; fallo real conservado |
| Luna/Appium 1 | 32 | 52 075 | Resumen S/ 12.34; rechazo de seguridad antes del pago |
| Terra/CuyScout 1 | 1 | 27 | Puerto incorrecto: preparación inválida del coordinador |
| Terra/CuyScout 2 | 20 | 4 855 | Resumen S/ 23.50; rechazo de seguridad; luego se confirmó defecto de tipos del exportador |

No se borraron fallos para seleccionar solo éxitos. Las repeticiones CuyScout siguen las dos reparaciones del producto; Luna/Appium se repitió tras autorización renovada. Los registros anteriores están separados de las últimas corridas.

Luna/CuyScout 2 recibió HTTP 200 con `value.sessionId=4D5155A3-FBB9-426C-949E-7090CBB9E591`, volvió a crear sesión y recibió HTTP 400 por simulador ocupado. Su afirmación de no haber recibido ID contradice la respuesta. El coordinador cerró esa sesión huérfana directamente, fuera del medidor; ese DELETE no está incluido en sus tres llamadas.

## Reparaciones de CuyScout y rollback

1. **`043f12d`:** ayuda específicamente HTTP, cuerpo de acción crudo en vez de argumentos MCP, errores de cliente 400 útiles en lugar de 500 genérico, y controlador externo de corridas. La primera corrida Luna/CuyScout se cortó al aparecer el defecto.
2. **`51c3bb6`:** el helper TypeScript declaraba `Promise<WebdriverIO.Element>` pero devolvía `ChainablePromiseElement`, incompatible con WebdriverIO 9.32.0. También fallaba el helper original del exportador, no solo la adaptación de Terra. Ahora devuelve `element.getElement()`. Tras confirmarlo se detuvo la publicación definitiva y se repitió CuyScout desde cero con tareas y simuladores nuevos.

Verificación: **211 pruebas Swift**, **6 del controlador**, contratos HTTP/MCP y comprobación TypeScript del helper reparado, todos aprobados. Los cambios están en commits independientes; las correcciones no alteran los archivos originales archivados.

## Originales y reproducción

WebdriverIO 9.32.0, tsx 4.23.15, TypeScript 7.0.2, Appium 3.2.2 / XCUITest 10.32.0. Copias exactas con SHA-256; las copias de ejecución solo cambian extensión a `.mts` para ESM. No se repararon los scripts de los agentes para presentarlos como éxitos autónomos.

| Archivo original vigente | TypeScript | Ejecución independiente |
|---|---|---|
| [Luna/CuyScout](cuyscout-luna-attempt3-original.ts) | Pasa | Código 1: `label_service_summary_name` no se mostró en 10 s; no llegó al pago; cerró sesión |
| [Luna/Appium](appium-luna-attempt2-original.ts) | TS2322: falta `firstMatch` en capabilities W3C | No ejecutado: parcial, sin comprobante y pago rechazado |
| [Terra/CuyScout](cuyscout-terra-attempt3-original.ts) | Pasa | Código 1: el límite de 200 llamadas cortó el sondeo de visibilidad de `btn_service_pay`; no llegó al pago; cerró sesión |
| [Terra/Appium](appium-terra-original.ts) | 13 TS2592: `$` no definido | Código 1: `ReferenceError: $ is not defined` antes del login; cerró sesión |

El original de Luna/CuyScout usa `waitForDisplayed` también para leer los textos del resumen. En la reproducción, el elemento fue localizado pero `displayed` devolvió false; el script falló antes de pagar. Esto difiere del `waitForExist` del helper exportado. No se afirma una causa de visibilidad adicional sin evidencia, ni se atribuye automáticamente al servidor CuyScout, que no participa en el replay Appium.

Terra/CuyScout también usó `waitForDisplayed`, esta vez para el botón final, que fue localizado pero no se mostró. El sondeo alcanzó 200 peticiones; el controlador respondió 429 y el SDK agotó sus reintentos de lectura acotados. DELETE siguió permitido y cerró la sesión. No se repitió con límites mayores ni se modificó el original para convertir el resultado en éxito. **Ninguno de los cuatro originales acreditó una reproducción completa.**

Las reproducciones están separadas del tráfico exploratorio. La de Luna/CuyScout tiene 117 llamadas y 6 981 tokens; la de Terra/Appium tiene 3 llamadas y 336 tokens. Los totales de las tres reproducciones están en [replay-metrics.json](replay-metrics.json). Para reproducciones se permitieron hasta 200 llamadas/180 s (Terra/Appium: 80/120 s), porque las esperas WebdriverIO generan sondeos de atributos; no son decisiones del agente.

SHA-256 de los originales vigentes:

```text
67fbc55a06115de8e2d541f544c76fd4a712c053041690654a5af9cd431fc6c1 cuyscout-luna-attempt3-original.ts
861ee32c1e019716b9a9dc3e95110099b537f38ff1d94f21232420c5da743b78 appium-luna-attempt2-original.ts
a4fd6f3f67831237faf2c5da8f83b08db12f4d77939def15be0003a403cbe506 cuyscout-terra-attempt3-original.ts
b71faa4f65bbd87bd14a2459420a8ba01951b9474d5a72d2cfae3f0e7b709b26 appium-terra-original.ts
```

Los originales anteriores y sus errores de tipos también se conservan; no deben confundirse con las versiones de las últimas corridas. [Verificación detallada](VERIFICACION.md).

## Evidencia reproducible

[Metodología y límites](METODOLOGIA.md), [manifest con tareas e intentos](manifest.json), [métricas calculadas](metrics.json), prompts, auditorías y logs de este directorio. Recalcular el tráfico exploratorio y Sonnet:

```sh
python3 Scripts/evidence/run-20260922-luna-terra/summarize.py
```

El script excluye explícitamente replays y archivos de control. No hubo dinero real. Las sesiones se cerraron; solo una limpieza de sesión huérfana fue realizada por el coordinador fuera del medidor, documentada arriba.
