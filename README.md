# CuyScout

CuyScout es una base Swift para automatización de dispositivos con una API HTTP local inspirada en WebDriver/Appium. Sí, Swift es una buena opción para el núcleo en macOS: permite integrar `simctl`, XCTest/XCUITest y APIs nativas con poca fricción.

## Cuánto cuesta, medido

El mismo escenario Gherkin —iniciar sesión, pagar un recibo de Sedapal, verificar el código
de operación— ejecutado por seis agentes sin acceso al código de la app: tres con CuyScout y
tres con Appium 3.2.2, uno por modelo, sobre simuladores iguales.

| Modelo | CuyScout | Appium 3.2.2 | Ventaja |
|---|---:|---:|---:|
| Opus 5 | **3 946** | 65 476 | 16,6x |
| Sonnet 5 | **3 689** | 72 199 | 19,6x |
| Haiku 4.5 | **9 525** | 154 759 | 16,2x |

Tokens reales sobre el tráfico HTTP, contados con `cl100k_base` por un proxy idéntico
delante de cada servidor. Los seis agentes completaron el pago.

La diferencia no está en el protocolo sino en qué obliga a transportar. Una vuelta del bucle
en Appium es `GET /source`: el árbol XML entero, del que casi todo es geometría y
contenedores anónimos de SwiftUI que no se pueden accionar. En CuyScout es `GET /observe`,
que devuelve en una sola llamada los controles accionables con su selector (`actions`) y los
textos visibles para verificar (`texts`). En la pantalla de comprobante de la app de prueba,
esa observación cuesta **284 tokens** frente a **2 043** del árbol completo.

La ventaja es estructural, no del modelo: CuyScout varía un 7 % entre Opus y Sonnet porque su
coste lo fija el servidor, mientras que Appium varía un 10 % porque depende de cuántas veces
el agente decide releer el árbol, que sí es decisión suya.

**Dos advertencias para leer la tabla con honestidad.** Las dos corridas de Appium con Opus
difirieron un 25 % entre sí con el mismo prompt, así que la ventaja se reporta como orden de
magnitud y no como cifra exacta. Y las cifras de Appium son tokens en el cable: uno de sus
agentes montó una tubería de shell que descartaba el 93-94 % del XML antes de leerlo, lo que
reduce mucho el coste real en su contexto —pero esa defensa exige shell con tuberías y
desaparece para un cliente que hable por MCP.

Reporte completo, registros crudos de las seis corridas y las dos herramientas de medición en
[`Scripts/evidence/run-20260902-benchmark-appium/`](Scripts/evidence/run-20260902-benchmark-appium/),
para poder repetirlo.

## Automatizar una app solo con su instalador

Un agente puede conducir una app sin su código fuente: basta el entregable. `appium:app`
acepta un `.app` de simulador o un `.ipa`, del que CuyScout extrae el `Payload/*.app`, lee
`CFBundleIdentifier` del `Info.plist`, instala con `simctl` y lanza su runner XCTest genérico
prebuilt. A partir de ahí el agente observa y decide; no necesita conocer un solo selector
de antemano.

```bash
curl -X POST http://127.0.0.1:4723/session -H 'Content-Type: application/json' -d '{
  "capabilities": { "alwaysMatch": {
    "appium:app": "/ruta/a/MiApp.ipa",
    "appium:automationName": "XCUITest"
  }}}'
```

El flujo que debe seguir el agente —observar, decidir, ejecutar, verificar antes de una
acción irreversible y exportar la prueba— está en [AGENT-GUIDE.md](AGENT-GUIDE.md), con el
recorrido completo de un caso real: iniciar sesión y transferir S/ 100 entre cuentas propias
partiendo únicamente de un `.ipa`.

Para reproducir ese ejemplo, `Scripts/build_cuywallet_installer.sh` genera el instalador de
la app de demostración y `Scripts/build_scout_runner.sh` compila el runner una sola vez.

## Ejecutar

```bash
cd CuyScout
swift run cuyscout
```

Por defecto escucha en `127.0.0.1:4723`. Cambia el puerto con `swift run cuyscout 4724`.

## API mínima

```bash
curl http://127.0.0.1:4723/status
curl http://127.0.0.1:4723/devices
curl http://127.0.0.1:4723/doctor
curl http://127.0.0.1:4723/conformance
curl -X POST http://127.0.0.1:4723/session -H 'Content-Type: application/json' \
  -d '{"deviceId":"SIMULATOR_UDID","bundleIdentifier":"com.example.app"}'
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/actions \
  -H 'Content-Type: application/json' -d '{"type":"launch","bundleIdentifier":"com.example.app"}'
curl http://127.0.0.1:4723/session/SESSION_ID/screenshot --output screen.png
```

Acciones disponibles: `launch`, `terminate`, `openURL`, `screenshot`, `tap`, `swipe`, `type` y `accessibilityTree`.

La API HTTP también acepta una primera capa W3C WebDriver con `POST /session`, `findElement`, `findElements` (múltiples referencias reales), click, escritura, texto, `enabled`, `rect`, `GET /session/SESSION_ID/title` y `GET /session/SESSION_ID/source`.

Las acciones semánticas y assertions nativas se enrutan al puente XCTest/XCUITest (`findElement`, `tapElement`, `typeElement`, `waitFor`, `assertVisible` y `assertText`); registra el runner antes de usarlas.

Las búsquedas sin coincidencia siguen el error W3C `no such element` con HTTP 404, compatible con clientes WebDriver/Appium.

El screenshot de elemento nativo se enruta al runner XCTest y está disponible en `GET /session/SESSION_ID/element/ELEMENT_ID/screenshot`. En WebView, CuyScout captura elementos `<canvas>`, `<img>` y DOM HTML general como PNG recortando la captura real según el rectángulo del elemento; WebKit Inspector sigue siendo necesario para captura nativa del viewport.

Una referencia de elemento desconocida o expirada devuelve `stale element reference` con HTTP 404 para que el agente vuelva a localizarla.

WebView soporta búsqueda relativa W3C con `POST /session/SESSION_ID/element/PARENT_ID/element` y `/elements` cuando padre e hijo usan selectores CSS; Native y otras estrategias requieren soporte XCTest dedicado.
También está disponible por MCP con `cuyscout_find_element_from_element` y `cuyscout_find_elements_from_element`.

Una sesión W3C también puede consultarse con `GET /session/SESSION_ID`, que devuelve el `sessionId` y las capabilities negociadas (`platformName`, `automationName`, `driverId`, dispositivo, runtime y bundle). También están disponibles directamente en `GET /session/SESSION_ID/capabilities` o MCP `cuyscout_session_capabilities`; incluyen el puerto de automatización aislado cuando existe.

La navegación estándar está disponible con `POST /session/SESSION_ID/back`, `/forward` y `/refresh`. En `NATIVE_APP` requiere una sesión web/híbrida; en `WEBVIEW` se traduce a `history.back()`, `history.forward()` y `location.reload()`.

Las alertas del sistema se controlan con las rutas W3C `POST /session/SESSION_ID/alert/accept` y `POST /session/SESSION_ID/alert/dismiss` (también existen aliases `accept-alert` y `dismiss-alert`). El runner XCTest selecciona el botón principal o el último botón de la alerta, respectivamente.
El texto se puede consultar de forma compacta con `GET /session/SESSION_ID/alert/text` o MCP `cuyscout_get_alert_text`, que devuelve el texto y botones detectados sin descargar todo el árbol de accesibilidad.

La orientación se consulta y cambia con `GET/POST /session/SESSION_ID/rotation`, usando `portrait`, `portraitUpsideDown`, `landscapeLeft` o `landscapeRight`. En simuladores usa `simctl` y en el runner XCTest usa `XCUIDevice`.

El clipboard usa endpoints Appium compatibles: `GET /session/SESSION_ID/appium/device/get_clipboard` y `POST /session/SESSION_ID/appium/device/set_clipboard`. En el runner XCTest se conecta con `UIPasteboard`.

El lifecycle del simulador incluye instalación, desinstalación y reset: `POST /session/SESSION_ID/appium/device/install_app`, `remove_app` y `reset_app`. También están disponibles por MCP como `cuyscout_install_app`, `cuyscout_remove_app` y `cuyscout_reset_app`.

También se puede activar o terminar la app con `POST /session/SESSION_ID/appium/device/activate_app` y `terminate_app`, o mediante `cuyscout_activate_app` y `cuyscout_terminate_app`.

Para probar recuperación tras background, usa `POST /session/SESSION_ID/appium/device/background_app` con `{ "seconds": 2 }` o MCP `cuyscout_background_app`. El runner XCTest envía Home y espera el tiempo indicado.

`GET /session/SESSION_ID/page-info` y la herramienta MCP `cuyscout_page_info` devuelven contexto, URL, título y tamaño de la fuente sin descargar el DOM completo, reduciendo llamadas y tokens durante la exploración.

La herramienta MCP `cuyscout_action_suggestions` analiza los controles visibles —accesibilidad XCTest en `NATIVE_APP` y DOM en `WEBVIEW`— y propone `tapElement` o `typeElement` con un selector estable. En campos de texto usa el marcador `<text>` para que el agente decida el dato real.

La misma información está disponible por HTTP en `GET /session/SESSION_ID/action-suggestions?max=20`.

Para pedir directamente el catálogo de acciones ejecutables usa MCP `cuyscout_available_actions` o HTTP `GET /session/SESSION_ID/available-actions?maxActions=20`. Es un alias orientado a agentes que conserva selectores semánticos y el marcador `<text>` sin descargar nuevamente el árbol completo.

Para explorar con una sola llamada usa MCP `cuyscout_observe` o HTTP `GET /session/SESSION_ID/observe?maxActions=20`. Devuelve contexto, URL, título, `stateId`, si la pantalla cambió, acciones disponibles y estado de la exploración. Cada acción sugerida incluye `risk` (`low`, `medium` o `high`); los controles destructivos y campos sensibles se marcan para que el agente decida explícitamente. El `stateId` es estable frente a timestamps, UUIDs y contadores dinámicos, evitando que esos cambios creen pantallas falsas y ciclos redundantes.

Para una decisión completa del agente usa `cuyscout_agent_state` o `GET /session/SESSION_ID/agent-state`. Combina observación, métricas, últimos eventos, cobertura de exploración, preparación de sesión y una sugerencia de siguiente acción en una sola respuesta. Prioriza `connect_xctest_bridge`, `connect_webview_adapter` o `stop_session_or_create_new` cuando hay bloqueos; después de un fallo puede recomendar `inspect_last_error_and_retry_resilient`; si la pantalla no cambió, recomienda `use_accessibility_diff`. `loopDetected`, `coverage.loopRisk` y `readiness.blockers` evitan repetir exploraciones bloqueadas. Las lecciones devueltas se ordenan por relevancia contextual: escritura/teclado, selectores, latencia o bucles recientes. Se puede limitar con `maxActions` y `recentEvents`; `lightweight=true` omite accesibilidad para polling económico.

Si el puente XCTest todavía no está conectado, `cuyscout_agent_state` no falla: devuelve una observación mínima y el bloqueo `xctest_bridge_not_registered`, evitando reintentos automáticos inútiles.

La política de seguridad acepta `maxCommandsPerSession` y `deniedActionTypes` para limitar comandos concretos de una sesión. La denylist se aplica recursivamente dentro de `sequence` y batch y compara los nombres sin distinguir mayúsculas. La política completa y el contador son independientes de la retención de eventos y se conservan en los artefactos, por lo que las restricciones no se pierden al restaurar la sesión. `0` mantiene el comportamiento ilimitado; al alcanzar otro valor, CuyScout rechaza comandos adicionales con `Session command budget exhausted`. El estado del agente expone `commandsUsed`, `commandsRemaining` y el bloqueo `command_budget_exhausted` antes de llegar al error.

La auditoría de seguridad se consulta con MCP `cuyscout_security_audit` o `GET /session/SESSION_ID/security-audit`; registra acciones permitidas y bloqueadas, marca acciones sensibles y conserva el motivo.

Para consultar solo disponibilidad usa `cuyscout_session_readiness` o `GET /session/SESSION_ID/readiness`; esta ruta no lee el árbol de accesibilidad y es adecuada para decidir si conviene conectar XCTest/WebView antes de continuar.

Para una decisión completa de salud usa MCP `cuyscout_session_health` o `GET /session/SESSION_ID/health`; combina readiness, bloqueos, presupuesto de comandos, tasa de fallos y p95 sin transferir eventos completos.

CuyScout incluye memoria de lecciones aprendidas en `Application Support/CuyScout/lessons.json` o `CUYSCOUT_LESSONS_FILE`. Registra aprendizajes con MCP `cuyscout_record_lesson` o `POST /lessons` usando scopes `global`, `project` o `session`; consulta las lecciones aplicables con `cuyscout_list_lessons`, `GET /lessons` o `GET /session/SESSION_ID/lessons`. Las consultas aceptan texto (`query` en MCP, `q` en HTTP), `tags`, `scope` y `limit`. Las repeticiones se consolidan, incrementan `occurrences` y elevan su confianza, evitando contexto duplicado. `agent-state` incluye las cinco lecciones con más recurrencia y confianza para que el agente recuerde advertencias como “el teclado tapa el campo; desplázate antes de escribir”. No deben guardarse secretos ni datos personales como lecciones.

El aprendizaje puede ejecutarse con MCP `cuyscout_learn_from_session` o `POST /session/SESSION_ID/lessons/learn`. `persist: false` permite revisar candidatos antes de guardarlos. Al finalizar una exploración, CuyScout aprende automáticamente patrones con evidencia suficiente: fallos repetidos, ciclos, comandos lentos y posibles controles ocultos por el teclado. La evidencia es estructural y nunca incluye el texto escrito por el agente.

Cuando una lección es aplicable al último evento, `agent-state` la convierte en una sugerencia compacta como `dismiss_keyboard_or_scroll_before_next_control`, `repair_selector_before_retry` o `wait_for_semantic_stability_before_retry`.

Antes de exportar una grabación, `cuyscout_validate_test_plan` valida pasos fallidos, secuencias vacías, selectores vacíos o frágiles, coordenadas, placeholders, datos sensibles y exportaciones vacías. `valid` indica consistencia del plan y `executable` indica si todas sus acciones pueden reproducirse automáticamente.

También valida marcadores estructurales de XCTest, WebdriverIO JavaScript/TypeScript, Appium Python, Appium Java, Gherkin y el array JSON portable. Esto detecta exportaciones truncadas o mal formadas antes de entregarlas al agente.

La exportación `generatedAppiumTypeScript` es TypeScript real para WebdriverIO: incluye `WebdriverIO.Browser`, `WebdriverIO.Element` y tipos en la función de búsqueda. La exportación `generatedAppium` conserva JavaScript para proyectos que no usan compilación TypeScript.

El servidor MCP también expone recursos de solo lectura para reducir llamadas y tokens: `cuyscout://lessons`, `cuyscout://session/{sessionId}/agent-state`, `cuyscout://session/{sessionId}/lessons` y `cuyscout://session/{sessionId}/report`, mediante `resources/list`, `resources/templates/list` y `resources/read`.

La creación W3C de sesión combina `alwaysMatch` con cada candidato `firstMatch`, descarta conflictos y devuelve `invalid argument` si ninguna combinación es compatible. `CapabilityNegotiator` es reutilizable por HTTP y futuras entradas MCP; normaliza aliases como `automationName` a `appium:automationName`. Se aceptan `platformName=iOS|any` y `appium:automationName=XCUITest` para el driver actual.

El gateway acepta tanto rutas W3C en la raíz (`/session`) como el prefijo Appium tradicional (`/wd/hub/session`). El smoke test admite `CUYSCOUT_BASE_PATH=/wd/hub` para verificar ambas formas.

Los recursos `cuyscout://session/{sessionId}/events?after=N&kind=command.failed` y `cuyscout://session/{sessionId}/batch-summary?requestId=...` permiten consumir cambios incrementales y diagnósticos compactos mediante MCP sin polling de herramientas.

También ofrece el prompt MCP `cuyscout_explore_to_test` mediante `prompts/list` y `prompts/get`. Recibe `sessionId` y un objetivo opcional y entrega el flujo recomendado de exploración, aprendizaje, validación, reparación revisable, replay y exportación.

Después de un batch, el agente puede consultar `cuyscout_batch_summary` o `GET /session/SESSION_ID/batch-summary?requestId=...`. El resumen solo contiene ejecución, índices fallidos, categorías, cantidad reintentable y `nextActionHint`, evitando transferir todos los pasos y resultados.

Los timeouts W3C se consultan y configuran con MCP `cuyscout_get_timeouts`/`cuyscout_set_timeouts` o HTTP `GET/POST /session/SESSION_ID/timeouts`. Aceptan `implicit`, `pageLoad` y `script` en milisegundos; solo se admiten valores finitos y no negativos.

Para ejecutar varios pasos con una sola llamada usa `cuyscout_execute_batch` o `POST /session/SESSION_ID/batch` con `actions`. Devuelve el resultado por índice, detiene el lote en el primer fallo por defecto y acepta `resilient`, `stopOnError`, `includeResults` y `timeoutSeconds` (máximo 120 segundos); este último está desactivado para evitar transferir screenshots o payloads grandes. Usa `requestId` para que un reintento del agente sea idempotente y no repita acciones en el dispositivo.

Antes de ejecutar, `cuyscout_validate_batch` o `POST /session/SESSION_ID/batch/validate` detecta batches vacíos, secuencias vacías y placeholders que requieren datos del agente.

Un batch con `requestId` puede cancelarse entre acciones mediante MCP `cuyscout_cancel_batch` o `POST /session/SESSION_ID/batch/cancel` con `{ "requestId": "..." }`. La acción que ya está ejecutándose termina; las siguientes no se ejecutan y el resultado marca `batch_cancelled`.

Cada paso fallido de un batch incluye `category`: `selector`, `infrastructure`, `environment`, `product` o `cancelled`. Con `retryInfrastructure=true` y `maxRetries` se pueden reintentar solo fallos de infraestructura, hasta tres veces, sin ocultar fallos reales del producto.

La ejecución batch también aplica esta validación automáticamente; los errores estructurales se rechazan antes de tocar el dispositivo, mientras que los placeholders se mantienen como advertencias.

Replay y restauración de checkpoints vuelven a aplicar la política de seguridad de la sesión y consumen el presupuesto de comandos; `resetApp` también requiere `allowLifecycle`.

Al eliminar una sesión, CuyScout libera también su política, presupuesto y estado auxiliar para evitar configuración huérfana en memoria.

La cobertura compacta está disponible con `cuyscout_exploration_coverage` o `GET /session/SESSION_ID/exploration-coverage`: resume estados, transiciones únicas, repeticiones, tasa de repetición y riesgo de bucle sin transferir el grafo completo.

Los contratos de pantalla están disponibles con `cuyscout_generate_screen_contract` o `POST /session/SESSION_ID/screen-contract`; luego pueden compararse con `cuyscout_compare_screen_contract` o `POST /session/SESSION_ID/screen-contract/compare` para detectar elementos faltantes, cambiados o inesperados.

La exploración también mantiene un grafo con `cuyscout_navigation_graph` o `GET /session/SESSION_ID/navigation-graph`, y checkpoints lógicos con `cuyscout_create_checkpoint`, `cuyscout_list_checkpoints` o `POST/GET /session/SESSION_ID/checkpoints`. Los checkpoints guardan identidad de pantalla y paso de grabación; la restauración física del estado será el siguiente bloque.

La fase de compilación comenzó con `cuyscout_get_test_plan` y `GET /session/SESSION_ID/recording/plan`, que normalizan pasos, duración y warnings antes de exportar XCTest/Appium.

La última grabación permanece consultable después de detenerla; los endpoints de recording, plan y exportación siguen disponibles durante el análisis posterior.

Para validar la prueba usa MCP `cuyscout_replay_recording` o `POST /session/SESSION_ID/recording/replay`. Devuelve éxito, pasos ejecutados, primer fallo y duración; acepta `optimized: true`, `resilient: true` y `variables: {"redacted":"valor-secreto", "text":"valor-de-prueba"}` para inyectar datos solo durante el replay.

El resultado también puede exportarse para CI con MCP `cuyscout_export_replay_junit` o `GET /session/SESSION_ID/recording/replay.junit.xml`; HTTP acepta `optimized=true&resilient=true`.

El proyecto incluye `.github/workflows/ci.yml`, que ejecuta `swift test --parallel` y una compilación release en macOS 14 para cada cambio que afecte CuyScout.

La matriz detallada de conformidad W3C/Appium está en [CONFORMANCE.md](CONFORMANCE.md), incluyendo soporte por contexto y validaciones que requieren un simulador o una app híbrida real. Para agentes y CI, `GET /conformance` o MCP `cuyscout_conformance` devuelve el mismo estado en formato compacto.

Las pruebas de humo están en `Tests/Conformance/`, junto con `requirements.txt`, `package.json` y una guía de ejecución: `w3c_smoke.sh` usa HTTP puro, `appium_python_smoke.py` usa `Appium-Python-Client` y `webdriverio_smoke.mjs` usa `webdriverio`. Ejecuta cualquiera con `CUYSCOUT_DEVICE_ID=...` y CuyScout más un simulador activos.
El workflow manual `.github/workflows/conformance.yml` prepara un iPhone Simulator, ejecuta los tres smoke tests y conserva el log del gateway como artifact.

Antes de exportar, usa `cuyscout_validate_test_plan` o `GET /session/SESSION_ID/recording/plan/validate` para detectar planes vacíos, pasos fallidos, placeholders `<text>` y acciones observacionales que requieren revisión.

La validación también detecta `<redacted>` cuando el artefacto fue protegido; esos valores deben parametrizarse antes de ejecutar la prueba exportada.

Para generar una versión compacta usa MCP `cuyscout_get_optimized_test_plan` o `GET /session/SESSION_ID/recording/plan/optimized`. El optimizador elimina únicamente consultas de inspección exitosas, incluso dentro de secuencias, y deja constancia del conteo en `warnings`. Conserva interacciones repetidas (taps, escritura, gestos y envío), waits, assertions y pasos fallidos; mantiene los IDs originales para rastrear cada paso hasta la grabación. No deduce que dos acciones iguales sean redundantes.

También puedes exportar Appium para TypeScript con `cuyscout_export_appium_typescript` o `GET /session/SESSION_ID/recording/appium/typescript`, y para Java con `cuyscout_export_appium_java`. Las exportaciones existentes incluyen WebdriverIO/JavaScript, Python, Gherkin y JSON portable.

La autocuración inicial está disponible con MCP `cuyscout_repair_selector` o `GET /session/SESSION_ID/selector/repairs?strategy=label&value=Continuar`. Devuelve alternativas con score y explicación; nunca modifica automáticamente la prueba.

Para ejecutar con autocuración usa MCP `cuyscout_execute_resilient` o `POST /session/SESSION_ID/actions?repair=true`. Si una acción semántica falla en Native o WEBVIEW, busca una alternativa con score mínimo de 0.6 y reintenta; también puede reparar pasos individuales dentro de una `sequence`. Si no hay una coincidencia confiable, conserva el error original.

Para revisar un cambio antes de aplicarlo usa MCP `cuyscout_preview_repair` o `POST /session/SESSION_ID/actions/repair-preview`. Devuelve la acción original, la propuesta, el score y el motivo con `requiresApproval=true`; no ejecuta la acción ni sobrescribe la prueba.

Las decisiones quedan registradas con MCP `cuyscout_repair_audit`, `GET /session/SESSION_ID/repairs` o `POST /session/SESSION_ID/repairs`. Las reparaciones aplicadas por `cuyscout_execute_resilient` también se registran y se incluyen en los artifacts; al exportar con redacción activa, sus acciones de escritura se guardan como `<redacted>`.

La memoria de lecciones aplica redacción automática a emails, tokens Bearer, campos `password`/`token`/`secret`/`apiKey` y números largos antes de persistirlos. Esto se suma a la redacción de grabaciones y artifacts.

La auditoría de accesibilidad está disponible con MCP `cuyscout_accessibility_audit` o `GET /session/SESSION_ID/accessibility-audit`. Detecta controles sin identifier, labels faltantes o ambiguos y áreas táctiles menores de 44 puntos, tanto en Native como en WEBVIEW. Al detener una exploración, `cuyscout_stop_exploration` y `POST /session/SESSION_ID/exploration/stop` adjuntan automáticamente `accessibilityAudit` cuando existe bridge o adaptador.
La auditoría final también se conserva en el artefacto persistido y se restaura junto con la sesión.

La reparación de selectores también inspecciona controles DOM en contexto WEBVIEW y propone selectores CSS alternativos basados en id, name, aria-label y texto.

El inspector agent-first puede consultar todo el contexto con MCP `cuyscout_session_report` o `GET /session/SESSION_ID/report`: puente, WebView, navegación, checkpoints, pasos grabados (incluidos los de una grabación detenida), métricas y conteo de problemas de accesibilidad.

El reporte visual se obtiene con `GET /session/SESSION_ID/report.html` o MCP `cuyscout_export_report_html`; es un HTML autocontenido para adjuntar en CI.

Para consultar rendimiento sin descargar eventos usa MCP `cuyscout_metrics` o `GET /session/SESSION_ID/metrics`. Devuelve total de comandos, tasa de fallos, promedio, p95 y conteo por acción; el historial se limita a los últimos 500 eventos para mantener el consumo acotado.

Para métricas del gateway completo usa MCP `cuyscout_fleet_metrics` o `GET /metrics`; devuelve sesiones activas, eventos retenidos, fallos y latencia promedio.

Los eventos fallidos incluyen ahora `error` con el motivo de la operación, útil para autocuración y diagnóstico sin repetir llamadas.

Para esperar cambios sin hacer polling usa MCP `cuyscout_wait_events` o `GET /session/SESSION_ID/events?after=EVENT_ID&timeout=10`. También existe el stream SSE `GET /session/SESSION_ID/events/stream?after=EVENT_ID&timeout=30`, que entrega `event: cuyscout.events` cuando aparece actividad. Puedes filtrar por `kind=command.failed` o `command.completed`. El timeout está limitado a 30 segundos. La retención predeterminada es de 500 eventos y puede ajustarse con `CUYSCOUT_EVENT_RETENTION` entre 10 y 10000.

El canal WebSocket BiDi `GET /session/SESSION_ID/events/websocket?after=EVENT_ID&kind=command.failed&maxDuration=300` completa el handshake RFC 6455 y entrega cada evento nuevo como frame de texto en cuanto ocurre, sin polling. Responde `ping` con `pong`, cierra limpio al recibir `close` y limita la conexión con `maxDuration` entre 1 y 3600 segundos; al vencer envía un frame `close` antes de desconectar.

El paquete portable de artefactos se obtiene con MCP `cuyscout_export_artifacts` o `GET /session/SESSION_ID/artifacts`. Usa el esquema `cuyscout.session-artifact.v1` e incluye sesión, eventos, métricas, checkpoints y plan de prueba para guardarlo en CI o almacenamiento externo.

La rehidratación está disponible con `POST /session/restore` o MCP `cuyscout_restore_artifacts`. CuyScout valida el esquema, la existencia y disponibilidad del simulador, evita duplicar IDs y vuelve a reservar el dispositivo antes de restaurar eventos, checkpoints y grabación.
Antes de restaurar, el agente puede ejecutar `POST /session/restore/validate` o MCP `cuyscout_validate_restore` para recibir errores y advertencias compactos sin adquirir el dispositivo.

Los artefactos exportados se persisten localmente de forma automática en `Application Support/CuyScout/artifacts`. `CUYSCOUT_ARTIFACT_DIR` permite elegir otro directorio; `GET /artifacts`, `GET /artifacts/catalog`, `POST /artifacts/SESSION_ID/restore`, `cuyscout_list_artifacts`, `cuyscout_artifact_catalog` y `cuyscout_restore_persisted_artifact` permiten descubrirlos y restaurarlos sin reenviar el JSON completo. El catálogo devuelve sesión, dispositivo, driver, eventos, pasos y URL; el paquete conserva URL actual, grafo de navegación y la última grabación aunque ya se haya detenido.

Por seguridad, los artefactos, el polling de eventos y las grabaciones/exportaciones redactan por defecto textos escritos, clipboard y valores esperados. Usa `CUYSCOUT_REDACT_SENSITIVE=false` solo en entornos controlados donde necesites reproducir datos exactos.

Los checkpoints se pueden restaurar con `cuyscout_restore_checkpoint` o `POST /session/SESSION_ID/checkpoints/CHECKPOINT_ID/restore`. Con `resetApp: true` intenta reiniciar la app antes del replay; de lo contrario informa que reproduce desde el estado actual.

El MCP también expone `cuyscout_doctor`. El diagnóstico marca como críticos Xcode Command Line Tools, Swift y `xcodebuild`; el proxy WebKit clásico aparece como opcional porque puede reemplazarse por otro adaptador Inspector.

Las sesiones aceptan `appium:driverId` en capabilities HTTP o `driverId` en `cuyscout_create_session`. El driver queda asociado a la sesión y se conserva en los artefactos restaurables.

Antes de crear la sesión, CuyScout valida que el driver declare soporte para `iOS` o `any`; un driver incompatible se rechaza sin dejar el simulador reservado.

Para evitar polling cuando no hay simuladores libres, usa `appium:sessionWaitTimeout` en capabilities o `waitSeconds` en MCP; la espera está limitada a 60 segundos.

El SDK de drivers está iniciado en `DriverAPI.swift`. `GET /drivers` y MCP `cuyscout_drivers` muestran drivers registrados y health checks; el driver de simulador iOS se registra por defecto.

El motor ya enruta las acciones compatibles a través del driver registrado. Las integraciones embebidas pueden usar `registerDriver`/`unregisterDriver` para sustituir el backend sin cambiar el motor de exploración.

El Plugin SDK está iniciado en `PluginAPI.swift`: permite hooks `before/after` sobre comandos, transformación de acciones y capacidades declarativas. `GET /plugins` y MCP `cuyscout_plugins` muestran plugins cargados.

Las integraciones Swift pueden registrar o retirar plugins con `registerPlugin`/`unregisterPlugin` en `ScoutEngine`; los hooks se aplican a todas las acciones de sus sesiones.

La política de seguridad por sesión se consulta y configura con `GET/POST /session/SESSION_ID/security-policy` o MCP `cuyscout_get_security_policy`/`cuyscout_set_security_policy`. Puede bloquear lifecycle, clipboard, coordenadas y URLs externas.

El canal inicial de eventos está disponible con `GET /session/SESSION_ID/events?after=0` y MCP `cuyscout_events`. Devuelve comandos completados o fallidos con duración, y deja preparado el formato para streaming BiDi futuro.

La paridad W3C incluye screenshots de elementos con `GET /session/SESSION_ID/element/ELEMENT_ID/screenshot`. XCTest devuelve el PNG recortado del control y WebView captura `<canvas>`/`<img>`; el adaptador WebKit Inspector sigue siendo necesario para DOM HTML general.

El timeout `implicit` de `POST /session/SESSION_ID/timeouts` ahora se aplica a `findElement` y `findElements`, con reintentos controlados hasta alcanzar el límite.

El mismo endpoint permite configurar `script`; los scripts JavaScript WebView esperan como máximo ese valor antes de devolver timeout al agente.

Para proteger el gateway HTTP define `CUYSCOUT_TOKEN`; las rutas requieren `Authorization: Bearer <token>`. `/status` y `/doctor` permanecen públicos para health checks.

Puedes limitar ese token con `CUYSCOUT_TOKEN_SCOPES=read,execute` o `admin`. `read` permite consultas, `execute` permite acciones HTTP y `admin` habilita configuración de seguridad, drivers, plugins y estado de artefactos. Si no se configura, el token mantiene acceso administrativo completo.

Configura `CUYSCOUT_LOG_FORMAT=json` para emitir una línea JSON por solicitud HTTP en stderr, con timestamp, `trace_id`, método, ruta, estado, `duration_ms` y error opcional. Los payloads y tokens no se registran.

CuyScout puede cargar configuración opcional desde `.cuyscout.yaml` al iniciar. Usa `.cuyscout.yaml.example` como plantilla y `.cuyscout.schema.json` para validarla en el editor o CI. `CUYSCOUT_CONFIG` permite indicar otra ruta; las variables de entorno explícitas tienen prioridad sobre el archivo. `server.bindAddress`/`CUYSCOUT_BIND_ADDRESS` permite cambiar la interfaz de escucha; el valor predeterminado es `127.0.0.1` por seguridad. Al usar una interfaz no local, `CUYSCOUT_TOKEN` es obligatorio.

El campo `server.profile` acepta `local`, `ci` o `device-farm`. `ci` activa logs JSON, redacción sensible y snapshots más frecuentes; `device-farm` activa logs JSON, redacción sensible y mayor retención de eventos. Los defaults nunca reemplazan una variable de entorno configurada explícitamente.

La configuración se valida antes de iniciar el gateway: perfiles, formato de logs, puertos, retenciones y booleanos fuera del schema hacen que CuyScout termine con un error explícito.

El servidor HTTP procesa conexiones concurrentemente, permitiendo que varias sesiones y runners trabajen en paralelo sin que un comando lento bloquee el resto.

El scheduler reserva un simulador y un puerto de automatización por sesión para evitar contaminación cruzada. Consulta leases y puertos con `GET /scheduler` o MCP `cuyscout_scheduler`; al eliminar la sesión ambos se liberan. Configura `CUYSCOUT_PORT_START` y `CUYSCOUT_PORT_COUNT` para elegir el rango.

El registro de workers remotos de device farm permite anunciar máquinas con capacidad propia. Registra un worker con `POST /workers` y JSON `{"url":"http://worker.host:4723","capabilities":["xcodebuild","ios-simulator"],"maxSessions":4}`; renueva su señal con `POST /workers/WORKER_ID/heartbeat` (`activeSessions` opcional) y dalo de baja con `DELETE /workers/WORKER_ID`. `GET /workers` lista estado `online`/`expired`, capacidad disponible, TTL y último heartbeat; sin señal el worker pasa a `expired` y deja de considerarse disponible hasta reactivarse con un heartbeat. Configura `CUYSCOUT_WORKER_TTL_SECONDS` entre 10 y 3600 segundos. Las herramientas MCP equivalentes son `cuyscout_register_worker`, `cuyscout_list_workers` y `cuyscout_worker_heartbeat`, y el dashboard de flota incluye `workersOnline` y `workersExpired`.

El runner XCTest puede diagnosticarse con `GET /session/SESSION_ID/bridge/status` o MCP `cuyscout_xctest_status`, que informa si está registrado, cuántos comandos esperan y cuándo tuvo actividad por última vez.

La capa W3C también soporta `clear`, `displayed`, atributos, screenshots en base64, `POST /timeouts` y acciones W3C simples de touch/keyboard. Para conservar una imagen PNG sin envelope usa `GET /session/SESSION_ID/screenshot/raw`.

Los endpoints de contexto están disponibles con `GET/POST /session/SESSION_ID/context` y `GET /session/SESSION_ID/contexts`. `NATIVE_APP` está disponible por defecto. Un adaptador WebKit puede registrar contextos `WEBVIEW_*` y recibir JavaScript mediante una cola dedicada:

```bash
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/webview/register \
  -H 'Content-Type: application/json' -d '{"contexts":["WEBVIEW_com.example.app"]}'
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/context \
  -H 'Content-Type: application/json' -d '{"name":"WEBVIEW_com.example.app"}'
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/execute/sync \
  -H 'Content-Type: application/json' -d '{"script":"document.title","args":[]}'
```

El adaptador debe consultar `GET /webview/command` y responder en `POST /webview/result`. La integración directa con WebKit Inspector/iOS y la resolución de elementos DOM quedan como el siguiente trabajo del driver; en este entorno no está instalado `ios_webkit_debug_proxy`.

Los execute methods W3C disponibles son:

```text
mobile: launchApp       {"bundleId":"com.example.app"}
mobile: terminateApp    {"bundleId":"com.example.app"}
mobile: openUrl         {"url":"https://example.com"}
mobile: getContexts
mobile: getScreenshot
mobile: getDeviceInfo
mobile: getDeviceTime
mobile: getPasteboard
mobile: setPasteboard   {"content":"..."}
```

Se invocan con `POST /session/SESSION_ID/execute/sync` o `execute/async` usando `{ "script": "mobile: getContexts", "args": [] }`.

La sesión también expone `GET/POST /session/SESSION_ID/url` y Settings Appium mutables en `GET/POST /session/SESSION_ID/appium/settings`.

Para ahorrar llamadas y tokens, también existen acciones semánticas: `findElement`, `tapElement`, `typeElement`, `waitFor`, `assertVisible`, `assertText`, `accessibilityTreeWithOptions`, `accessibilityDiff` y `sequence`. Los selectores nativos aceptan `accessibilityIdentifier`, `label`, `value`, `type` o `predicate`; en `WEBVIEW` también se aceptan `css selector` y `xpath`.

En WebView, las referencias obtenidas por `findElement` pueden reutilizarse con `click`, `value`, `clear`, `text`, `displayed` y `attribute`. CuyScout traduce estas acciones a JavaScript compacto y las envía al adaptador WebKit.

Ejemplo de prueba compacta en una sola llamada:

```json
{
  "type": "sequence",
  "actions": [
    {"type": "waitFor", "selector": {"strategy": "accessibilityIdentifier", "value": "emailField"}, "timeout": 10},
    {"type": "typeElement", "selector": {"strategy": "accessibilityIdentifier", "value": "emailField"}, "text": "user@example.com"},
    {"type": "tapElement", "selector": {"strategy": "label", "value": "Continuar"}},
    {"type": "assertVisible", "selector": {"strategy": "accessibilityIdentifier", "value": "dashboard"}}
  ]
}
```

Para obtener solo controles visibles y limitar la respuesta:

```json
{
  "type": "accessibilityTreeWithOptions",
  "options": {"visibleOnly": true, "interactiveOnly": true, "maxElements": 40}
}
```

El resultado de `findElement` contiene solo el elemento solicitado. Las assertions devuelven éxito o un error compacto, evitando enviar el árbol completo al agente.

El MCP incluye las herramientas `cuyscout_accessibility_tree`, `cuyscout_get_contexts`, `cuyscout_webview_status`, `cuyscout_register_webview`, `cuyscout_poll_webview`, `cuyscout_complete_webview`, `cuyscout_set_context` y `cuyscout_execute_script`. El árbol MCP limita por defecto la respuesta a 40 controles interactivos visibles, y JavaScript solo se permite después de seleccionar un contexto `WEBVIEW_*`.

`cuyscout_webview_status` permite al agente distinguir entre “la app no tiene WebView” y “el adaptador todavía no está conectado”, evitando reintentos inútiles.

`accessibilityDiff` guarda el último árbol por sesión y devuelve únicamente `added`, `removed` y `changed` en la siguiente lectura.

## Grabación de sesiones

**Toda sesión se graba desde que se crea.** Una corrida que no deja una prueba reutilizable
desperdicia el trabajo del agente, y depender de que alguien se acuerde de pedir
`recording/start` es depender de que no se olvide: al borrar la sesión, su artefacto queda
persistido con la grabación dentro. `CUYSCOUT_AUTORECORD=false` lo desactiva para quien solo
quiera explorar.

Las llamadas explícitas siguen disponibles para reiniciar la grabación o cerrarla antes de
tiempo:

```bash
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/recording/start

curl -X POST http://127.0.0.1:4723/session/SESSION_ID/actions \
  -H 'Content-Type: application/json' \
  -d '{"type":"tapElement","selector":{"strategy":"accessibilityIdentifier","value":"loginButton"}}'

curl -X POST http://127.0.0.1:4723/session/SESSION_ID/recording/stop \
  --output recorded-session.json
```

El archivo contiene `steps`, duración, resultado, errores y `generatedXCTest`. La grabación no almacena screenshots ni payloads grandes, para mantenerla liviana y apta para agentes. También está disponible por MCP con `cuyscout_start_recording`, `cuyscout_get_recording` y `cuyscout_stop_recording`.

Al detener una grabación, CuyScout persiste automáticamente el artefacto versionado de la sesión. La exportación explícita sigue disponible para obtenerlo bajo demanda.

Durante una sesión activa también se guarda un snapshot periódico cada 10 comandos. Configura `CUYSCOUT_AUTOSAVE_INTERVAL=0` para desactivarlo o usa otro intervalo positivo; el snapshot incluye la grabación, eventos, métricas, checkpoints y navegación disponibles hasta ese momento.

El estado de persistencia se consulta con MCP `cuyscout_artifact_status` o HTTP `GET /artifacts/status`, que devuelve disponibilidad, cantidad de artefactos, tamaño total, último guardado, frecuencia de autosave y retención configurada sin transferirlos.

Los leases del scheduler se mantienen con heartbeat en cada acción y expiran por defecto tras 15 minutos sin actividad. Configura `CUYSCOUT_LEASE_TTL_SECONDS` para cambiarlo; `GET /scheduler` y `cuyscout_scheduler` muestran `lastHeartbeat` y `expiresAt`.
Mientras el agente analiza una pantalla sin ejecutar acciones puede llamar `POST /session/SESSION_ID/heartbeat` o MCP `cuyscout_heartbeat` para renovar explícitamente el lease.

Las métricas globales también están disponibles en formato Prometheus con `GET /metrics?format=prometheus`, usando nombres `cuyscout_*` y content type compatible con scrapers estándar.

Configura `CUYSCOUT_ARTIFACT_RETENTION` con un número positivo para conservar solo los artefactos más recientes. `0` mantiene retención ilimitada, que es el comportamiento predeterminado.

En `WEBVIEW`, `source` devuelve el HTML del DOM y `title` el título actual; en `NATIVE_APP`, `source` devuelve el árbol de accesibilidad semántico.

La misma sesión incluye `generatedAppium`, un test JavaScript para Appium/WebdriverIO con capabilities W3C y `XCUITest`. También puede descargarse directamente:

```bash
curl http://127.0.0.1:4723/session/SESSION_ID/recording/appium \
  --output cuyscout.appium.test.js
```

Por MCP se obtiene con `cuyscout_export_appium`. Configura `IOS_UDID`, `IOS_BUNDLE_ID`, `IOS_DEVICE_NAME`, `APPIUM_HOST` y `APPIUM_PORT` antes de ejecutarlo.

También se genera `generatedAppiumPython` para `Appium-Python-Client`:

```bash
curl http://127.0.0.1:4723/session/SESSION_ID/recording/appium/python \
  --output test_cuy_scout.py
```

Por MCP se obtiene con `cuyscout_export_appium_python`. Instala las dependencias con `pip install Appium-Python-Client selenium` y ejecuta `python test_cuy_scout.py`.

## Exploración protegida contra bucles

El modo `exploration` inicia la grabación automáticamente y protege al agente contra ciclos, repeticiones de acciones, estados de accesibilidad repetidos, exceso de acciones y timeout.

```bash
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/exploration/start \
  -H 'Content-Type: application/json' \
  -d '{"maxActions":100,"maxStateRepeats":3,"maxActionRepeats":4,"timeoutSeconds":600}'

curl http://127.0.0.1:4723/session/SESSION_ID/exploration

curl -X POST http://127.0.0.1:4723/session/SESSION_ID/exploration/stop \
  --output exploration-result.json
```

El estado puede ser `loopDetected`, `actionLimitReached` o `timeout`, con la sugerencia `try_alternative_action`. En MCP están disponibles `cuyscout_start_exploration`, `cuyscout_exploration_status` y `cuyscout_stop_exploration`.

## Control UI y accesibilidad con XCTest

`tap`, `swipe`, `type` y `accessibilityTree` se ejecutan mediante el puente incluido en `XCUITestRunner/ScoutXCUITestBridge.swift`. Copia ese archivo a un target UI Testing de Xcode, configura las variables `CUYSCOUT_URL`, `CUYSCOUT_SESSION_ID` y `CUYSCOUT_BUNDLE_ID`, y llama a `ScoutXCUITestBridge().run()` desde un test UI. El runner registra el puente, recibe comandos y devuelve resultados a CuyScout.

Registrar el runner manualmente:

```bash
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/bridge
```

Ejecutar un tap:

```bash
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/actions \
  -H 'Content-Type: application/json' \
  -d '{"type":"tap","x":180,"y":420}'
```

Leer el árbol de accesibilidad:

```bash
curl -X POST http://127.0.0.1:4723/session/SESSION_ID/actions \
  -H 'Content-Type: application/json' \
  -d '{"type":"accessibilityTree"}'
```

La respuesta contiene `bundleIdentifier`, `count` y una lista `elements` con `type`, `identifier`, `label`, `value`, `enabled`, `exists` y `frame`.

## MCP para agentes

CuyScout incluye un servidor MCP por `stdio`:

```bash
cd CuyScout
swift run cuyscout-mcp
```

Registra ese comando en el cliente de agentes que uses. El servidor expone herramientas de estado, dispositivos, sesiones, ejecución, exploración, batches, cobertura, readiness, persistencia, XCTest y WebView; `tools/list` devuelve el catálogo completo y sus esquemas actualizados. El agente puede pedir una acción `accessibilityTree`, recibir el JSON y usar sus identificadores para decidir la siguiente acción.

## Próximos pasos recomendados

1. Añadir helpers de búsqueda por `accessibility identifier`, label y predicate en el runner.
2. Reemplazar el servidor HTTP mínimo por Vapor o Hummingbird si se necesita concurrencia, autenticación y WebDriver W3C completo.
3. Para dispositivos físicos, usar XCTest/XCUITest firmado y permisos de desarrollo; iOS no permite control arbitrario de otra app desde una app normal.

---

## 👨‍💻 Autor

**Oswaldo Leon** — oswaldo.leon9@gmail.com

## 💛 Patrocinar

¿Te resultó útil CuyScout? Considera patrocinar el proyecto:

[![PayPal](https://img.shields.io/badge/PayPal-Donate-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/oslh01)

CuyScout es código abierto y gratuito. Tu apoyo ayuda a mantener el proyecto, añadir
nuevas capacidades y seguir bajando el coste de automatizar apps iOS con agentes.
