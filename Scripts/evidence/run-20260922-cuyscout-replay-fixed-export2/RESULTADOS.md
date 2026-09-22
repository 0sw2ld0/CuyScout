# CuyScout: correcciones y reproducción verificada — 22 septiembre 2026

**Resultado: PASS del archivo generado por el exportador corregido**, sin editar su código,
en una instalación nueva de CuyWallet DEMO sobre simulador local. Esta es una regresión
de producto dirigida por el coordinador, **no una nueva corrida autónoma de Luna/Terra**.
Los resultados históricos de esos modelos se conservan sin cambiar sus fallos a éxitos.

## Los tres puntos

1. **Reproducción y esperas.** TypeScript ahora es autónomo (`tsx` + `webdriverio`), sin
   globals de Mocha ni adaptación manual. Conserva la semántica nativa: `waitFor` y
   `assertVisible` esperan existencia; `assertText` compara `label` y, si está vacío,
   `value`. El teclado hacía que WDA devolviera `displayed:false` para elementos que
   existían. El click normal de XCTest desplazó el botón antes de pulsarlo; no se
   usaron coordenadas ni se forzó un click. Los predicados traducen `identifier` a
   `name` para WDA sin modificar el contenido de literales entre comillas.
2. **Resumen antes de confirmar.** La ayuda HTTP y MCP exige observar después de
   completar los campos, reconocer resúmenes inline y registrar `assertText` antes del
   pago. Las sugerencias consideran el identificador y la etiqueta para advertir del
   riesgo de pagar/transferir/comprar. El riesgo es heurístico: un acceso al flujo no
   demuestra por sí solo que el botón confirma. En la prueba quedaron tres assertions
   de servicio, suministro y monto antes del único click de pago. Las secuencias ahora
   ejecutan sus hijos y se detienen en la primera falla.
3. **Archivo real en instalación limpia.** Se compiló y ejecutó el archivo generado
   desde la grabación preservada, con los datos redactados suministrados por variables
   de entorno. El código exportado y el ejecutado tienen exactamente el mismo SHA-256.
   Pasaron las tres comprobaciones previas, cuatro del comprobante y la búsqueda del
   número de operación no vacío mediante predicado.

La guía y la señalización de riesgo no son una garantía de que cualquier agente siga
las instrucciones. Volver a medir Luna/Terra requeriría nuevas corridas independientes.

## Evidencia final

- [Archivo exportado](original-export.ts), [parámetros DEMO](parameters.json).
- [Resultado de compilación/replay y hashes](replay-result.json), [salida completa](replay-output.txt).
- [Tráfico de replay](replay-http.jsonl): **94 llamadas, todas HTTP 200**, cierre de sesión incluido.
- Duración del replay: **26,329 segundos**; suma de latencias HTTP: 25,285 segundos.
- Límite externo: 200 llamadas / 180 segundos, más petición en curso; sin alcanzar el corte.
  El proceso de ejecución tiene además un límite de 180 segundos. Reintentos de transporte: cero.
- SHA-256: `21714fb34f8f9d9d2131069810bf8b6c5cb75f4cac5ebd9e2222031e3c3c4d6c`.
- Simulador de replay: `BCDE6C39-5D9C-4657-B0A6-596690B398BF`.
- [Grabación limpia de origen](../run-20260922-cuyscout-replay-fix-clean3/recording.json):
  resumen Sedapal / 19891201 / S/25.00; comprobante de exploración **SP630013**.
  El número se genera nuevamente durante el replay: no se compara con SP630013.

## Fallos conservados y reparados

- Antes del reinicio de la Mac se detectó que `sequence` se confundía con acciones W3C
  y después se enviaba al controlador de lifecycle. Se corrigieron ambas rutas y se
  descartaron esos intentos; aún no se había enviado pago en esa validación.
- [Primer intento posterior al reinicio](../run-20260922-cuyscout-replay-fix/http.jsonl):
  la observación inmediata al pago fue una transición vacía. No se repitió el click.
  Una captura diagnóstica confirmó SP638917 / S/25.00. Se añadió espera del comprobante.
- [Segundo intento](../run-20260922-cuyscout-replay-fix-clean2/http.jsonl): timeout del
  puente escribiendo el correo, antes de pagar. La revisión encontró un defecto HTTP
  independiente y reproducible: una sola lectura TCP no garantiza recibir el cuerpo.
  El servidor ahora espera el Content-Length completo, limita tamaño/tiempo y completa
  las escrituras. No se atribuye con certeza ese timeout concreto a la fragmentación.
- La grabación limpia siguiente terminó, pero su [primer exportado](../run-20260922-cuyscout-replay-fix-clean3/original-export.ts)
  no compiló por metadatos `options`. Se corrigió el tipo y se reexportó desde la misma
  grabación guardada, sin repetir la exploración ni alterar sus acciones.
- El [primer replay del exportado regenerado](../run-20260922-cuyscout-replay-fixed-export/replay-result.json)
  verificó resumen y comprobante, pero falló por `identifier`, atributo no admitido en
  predicados WDA. Se corrigió la traducción, se conservó ese archivo y se reinstaló la
  app DEMO antes de la reproducción final aprobada.

## Verificación de software

**218 tests Swift aprobados** (incluye compilación real TypeScript y rechazo de parámetros faltantes),
contratos HTTP/MCP y seis pruebas del controlador externo. La prueba de redacción usa
un secreto distintivo para evitar confundir la variable JavaScript `token` con una fuga.
Las pruebas HTTP cubren cabeceras/cuerpo separados y UTF-8 fragmentado, límites y
Content-Length ambiguo. Los simuladores propios y servidores quedaron detenidos.

Herramientas de regresión: [grabación HTTP](../../verify_sedapal_export.mjs),
[reexportación desde JSON](../../export_recording.swift), [compilación y replay](../../verify_export_replay.mjs).
Solo deben ejecutarse con autorización explícita de DEMO local. No comparan consumo de modelos.
