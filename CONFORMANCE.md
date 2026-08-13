# CuyScout — Matriz de conformidad

Estado de la primera implementación del gateway W3C/Appium.

| Área | Estado | Native | WEBVIEW | Notas |
|---|---|---:|---:|---|
| Crear/eliminar sesión | Implementado | Sí | Sí | Capabilities iOS exhaustivas con `app`, `noReset`, `fullReset`, `browserName` y más. |
| Consultar sesión/capabilities | Implementado | Sí | Sí | `GET /session/:id` y `/capabilities`. |
| Capabilities por MCP | Implementado | Sí | Sí | `cuyscout_session_capabilities` devuelve aliases W3C/Appium y puerto de sesión. |
| Snapshot de conformidad | Implementado | Sí | Sí | `/conformance` y `cuyscout_conformance` exponen estado compacto para CI/agentes. |
| Buscar elementos | Implementado | Sí | Sí | Referencias W3C, CSS/XPath en DOM. |
| Múltiples elementos | Implementado | Sí | Sí | Devuelve lista vacía cuando no hay coincidencias. |
| Búsqueda relativa | Implementado | Sí | Sí | Native vía XCTest `findElementFromElement`/`findElementsFromElement` y WebView CSS. |
| Búsqueda relativa por MCP | Implementado | Sí | Sí | `cuyscout_find_element(s)_from_element` acepta `strategy` para Native y WebView. |
| Click/escritura/clear | Implementado | Sí | Sí | Native requiere bridge XCTest. |
| Texto/atributo/displayed/enabled/rect | Implementado | Sí | Sí | Elementos W3C con referencias. |
| Screenshot de elemento | Parcial | Sí | Parcial | Native/XCUITest y WebView `<canvas>`/`<img>`; DOM general requiere Inspector WebKit real. |
| Page source/title | Implementado | Sí | Sí | Árbol compacto en Native, HTML en WEBVIEW. |
| Contextos híbridos | Parcial | Sí | Parcial | Adaptador WebKit externo/manual. |
| JavaScript sync/async | Parcial | No | Sí | Depende del adaptador WebView. |
| Alertas | Parcial | Sí | Parcial | Aceptar, descartar, lectura compacta y entrada de texto mediante XCTest; alertas WebView reales dependen del adaptador. |
| Orientación | Implementado | Sí | No | Simctl/XCTest. |
| Clipboard | Parcial | Sí | No | Requiere XCTest y política habilitada. |
| Implicit/script timeout | Implementado | Sí | Sí | Aplicado a búsquedas y scripts. |
| pageLoad timeout | Implementado | Sí | Sí | Aplicado a navegación WebView (`back`, `forward`, `refresh`, `openURL`). |
| Window rect | Implementado | Sí | Sí | `GET/POST /session/:id/window/rect` y MCP `cuyscout_window_rect`/`cuyscout_set_window_rect`. |
| Element selected | Implementado | Sí | Sí | `GET /element/:eid/selected` y MCP `cuyscout_element_selected`. |
| Element name | Implementado | Sí | Sí | `GET /element/:eid/name` y MCP `cuyscout_element_name`. |
| Element property | Implementado | Sí | Sí | `GET /element/:eid/property/:name` y MCP `cuyscout_element_property`. |
| Active element | Implementado | No | Sí | `GET /session/:id/element/active` y MCP `cuyscout_active_element`; Native devuelve nil. |
| Cookies | Implementado | No | Sí | `GET/POST/DELETE /session/:id/cookie` y MCP; WebView `document.cookie`. |
| Alert text (input) | Implementado | Sí | No | `POST /session/:id/alert/text` y MCP `cuyscout_set_alert_text`; Native vía XCTest. |
| Scroll/Wheel actions | Implementado | Sí | Sí | W3C `wheel` source en actions; `scroll(x,y)` por HTTP/MCP; Native vía bridge. |
| Permisos | Implementado | Sí | No | `POST /session/:id/appium/permissions` y MCP `cuyscout_grant_permission`; `simctl privacy grant`. |
| Biometría | Implementado | Sí | No | `POST /session/:id/biometry` y MCP `cuyscout_set_biometry`; `simctl biometry enable/disable`. |
| Geolocalización | Implementado | Sí | No | `POST /session/:id/geolocation` y MCP `cuyscout_set_location`; `simctl location set`. |
| Visual diff | Implementado | Sí | Sí | `POST /session/:id/visual-diff` y MCP `cuyscout_visual_diff`; comparación pixel a pixel con tolerancia configurable. |
| Timeline | Implementado | Sí | Sí | `GET /session/:id/timeline` y MCP `cuyscout_timeline`; entradas con acción, duración y error. |
| Timeouts W3C por MCP/HTTP | Implementado | Sí | Sí | Consulta y actualización de `implicit`, `pageLoad` y `script`. |
| Eventos/polling | Implementado | Sí | Sí | Polling y long-polling; BiDi push pendiente. |
| Stream SSE de eventos | Implementado | Sí | Sí | `/session/:id/events/stream` entrega el siguiente lote en formato `text/event-stream`; BiDi completo pendiente. |
| Replay y JUnit | Implementado | Sí | Sí | Replay normal, optimizado y resiliente. |
| Exportación Appium | Implementado | Sí | Sí | JavaScript, TypeScript, Python y Java; datos redactados por defecto. |
| Estado agent-first | Implementado | Sí | Sí | `cuyscout_agent_state`; incluye cobertura, readiness, bloqueos y recomendaciones. |
| Estado ligero/readiness | Implementado | Sí | Sí | `lightweight=true` y `cuyscout_session_readiness` evitan leer accesibilidad. |
| Salud compacta de sesión | Implementado | Sí | Sí | `cuyscout_session_health` y `/health` combinan readiness y métricas. |
| Memoria de lecciones | Implementado | Sí | Sí | Scopes global/project/session, deduplicación, recurrencia y búsqueda por texto/tags mediante MCP/HTTP; contexto compacto en `agent-state`. |
| Aprendizaje de sesión | Implementado | Sí | Sí | Inferencia bajo demanda y al cerrar exploraciones; detecta fallos repetidos, bucles, sincronización y posible obstrucción por teclado sin guardar texto escrito. |
| Validación de plan generado | Implementado | Sí | Sí | Valida consistencia, estabilidad de selectores, datos sensibles y posibilidad de ejecución antes de exportar. |
| Exportación TypeScript | Implementado | Sí | Sí | Genera WebdriverIO TypeScript tipado, además del exportador JavaScript. |
| Validación de exportadores | Implementado | Sí | Sí | Comprueba estructura mínima de XCTest, JS/TS, Python, Java, Gherkin y JSON portable. |
| Recursos MCP | Implementado | Sí | Sí | Expone resources/list, templates/list y read para estado, lecciones y reportes de sesión. |
| Prompts MCP | Implementado | Sí | Sí | Expone prompts/list y prompts/get con el flujo agent-first de exploración a prueba. |
| Resumen compacto de batch | Implementado | Sí | Sí | MCP/HTTP resume fallos y reintentos sin transferir el detalle completo de cada paso. |
| Recursos MCP incrementales | Implementado | Sí | Sí | URIs de eventos aceptan cursor `after` y filtro `kind`; batch-summary evita transferir resultados completos. |
| Negotiación alwaysMatch/firstMatch | Implementado | Sí | Sí | Combina matrices W3C, descarta conflictos y valida plataforma/automationName antes de crear sesión. |
| Prefijo `/wd/hub` | Implementado | Sí | Sí | El gateway normaliza `/wd/hub/*` y `/*`; el smoke test permite verificar ambos paths. |
| Reparación revisable | Implementado | Sí | Sí | MCP/HTTP devuelve parches de acción con evidencia y aprobación requerida sin ejecutar ni modificar la grabación. |
| Auditoría de autocuración | Implementado | Sí | Sí | Registra propuestas, aplicaciones y rechazos; los artifacts conservan la evidencia. |
| Redacción de auditoría | Implementado | Sí | Sí | Las acciones sensibles dentro de reparaciones se exportan como `<redacted>` cuando la redacción está activa. |
| Redacción de lecciones | Implementado | Sí | Sí | La memoria elimina emails, tokens, secretos y números largos antes de escribirlos en disco. |
| Auditoría al finalizar exploración | Implementado | Sí | Parcial | `stop_exploration` adjunta `accessibilityAudit` cuando existe bridge/adaptador. |
| Auditoría en artefactos | Implementado | Sí | Parcial | La auditoría final se persiste y restaura junto con la sesión. |
| Ejecución batch | Implementado | Sí | Sí | Validación previa, timeout, `requestId` idempotente y reparación resiliente opcional. |
| Cancelación de batch | Implementado | Sí | Sí | `cuyscout_cancel_batch` y `/batch/cancel` detienen pasos posteriores. |
| Clasificación de fallos | Implementado | Sí | Sí | Cada fallo de batch incluye categoría operativa para reintentos selectivos. |
| Reintentos de infraestructura | Implementado | Sí | Sí | `retryInfrastructure` y `maxRetries` reintentan solo fallos recuperables. |
| Protección contra loops | Implementado | Sí | Sí | Presupuesto por sesión, límites de exploration y recomendaciones de recuperación. |
| Persistencia/autosave | Implementado | Sí | Sí | Artefactos versionados al detener, snapshots periódicos y retención configurable. |
| Contratos de pantalla | Implementado | Sí | Parcial | Generación/comparación accesible; requiere bridge para Native. |
| Métricas Prometheus | Implementado | Sí | Sí | `GET /metrics?format=prometheus`. |
| Auditoría de seguridad | Implementado | Sí | Sí | `cuyscout_security_audit` y `/security-audit`. |
| Scopes Bearer | Implementado | Sí | Sí | `CUYSCOUT_TOKEN_SCOPES=read,execute,admin`. |
| Logs JSON | Implementado | Sí | Sí | `CUYSCOUT_LOG_FORMAT=json`, salida segura en stderr con `trace_id` y `duration_ms`. |
| Configuración YAML | Implementado | Sí | Sí | `.cuyscout.yaml` opcional, `.cuyscout.schema.json` y variables de entorno con prioridad. |
| Bind configurable | Implementado | Sí | Sí | `server.bindAddress`/`CUYSCOUT_BIND_ADDRESS`; `127.0.0.1` por defecto. |
| Seguridad de bind remoto | Implementado | Sí | Sí | Bind no local requiere `CUYSCOUT_TOKEN`. |
| Perfiles operativos | Implementado | Sí | Sí | `local`, `ci` y `device-farm` con defaults de seguridad y observabilidad. |
| Validación de configuración | Implementado | Sí | Sí | Rechaza perfiles, rangos y tipos inválidos antes de iniciar el gateway. |
| Aislamiento de puertos | Implementado | Sí | Sí | El scheduler reserva un puerto exclusivo por sesión y lo libera al cerrar. |
| Available actions agent-first | Implementado | Sí | Sí | `cuyscout_available_actions` y `/available-actions` devuelven acciones semánticas compactas. |
| Plugin allowlist | Implementado | Sí | Sí | `PluginRegistry.setAllowlist` filtra plugins no autorizados antes del registro. |
| Driver capabilities declarativas | Implementado | Sí | Sí | `DriverDescriptor` declara `supportedCapabilities` y `supportedSettings` por driver. |
| Cola de sesiones con prioridad | Implementado | Sí | Sí | `POST /scheduler/queue` y MCP `cuyscout_enqueue_session`; prioridades low/normal/high/urgent. |
| Dashboard de flota | Implementado | Sí | Sí | `GET /dashboard` y MCP `cuyscout_fleet_dashboard`; sesiones activas, cola, dispositivos y salud. |
| Caché de aplicaciones | Implementado | Sí | Sí | `POST /app-cache` y MCP `cuyscout_cache_app`; reutiliza rutas para instalación rápida. |
| Logs de consola | Implementado | Sí | Sí | `GET/POST /session/:id/console` y MCP `cuyscout_console_logs`/`cuyscout_record_console_log`. |
| Reglas reactivas | Implementado | Sí | Sí | `GET/POST/DELETE /session/:id/reactive-rules` y MCP; ejecuta acción al detectar evento. |
| TLS configurable | Implementado | Sí | Sí | `CUYSCOUT_TLS_CERT`/`CUYSCOUT_TLS_KEY` validados al arranque; `.cuyscout.yaml` soporta `server.tls`; `main.swift` pasa rutas al servidor. |
| Fingerprints semánticos | Implementado | Sí | Sí | `GET/POST /session/:id/fingerprints` y MCP; registra y busca fingerprints para autocuración. |
| Comparación de comportamiento | Implementado | Sí | Sí | `POST /session/:id/behavior-compare` y MCP; compara éxito esperado vs observado. |
| Rutas de plugins | Implementado | Sí | Sí | `GET /plugins/routes` y MCP; plugins pueden registrar endpoints HTTP custom. |
| Manifests de drivers | Implementado | Sí | Sí | `GET/POST /drivers/manifests` y MCP; carga dinámica de drivers desde Bundle. |
| Submit de elemento | Implementado | Sí | Sí | `POST /element/:eid/submit` y acción `submit`; Native vía bridge. |
| Captura de tráfico de red | Implementado | Sí | Sí | `GET/POST /session/:id/network` y MCP; retención configurable. |
| Sharding | Implementado | Sí | Sí | `GET/POST /session/:id/shard` y MCP; distribuye pasos por shardIndex/shardCount. |
| OpenTelemetry | Implementado | Sí | Sí | `GET/POST /session/:id/otel` y MCP; registra spans con traceID y parentSpanID. |
| Firma de plugins | Implementado | Sí | Sí | `PluginDescriptor.signature` opcional para validación de integridad. |
| Replay con resetApp | Implementado | Sí | Sí | `replayRecording(resetApp: true)` termina y relanza la app antes de reproducir. |
| Apariencia (dark/light) | Implementado | Sí | No | `POST /session/:id/appearance` y MCP `cuyscout_set_appearance`; `simctl ui appearance`. |
| Barra de estado | Implementado | Sí | No | `POST /session/:id/status-bar` y MCP `cuyscout_set_status_bar`; `simctl status_bar override`. |
| Grabación de video | Implementado | Sí | No | `POST /session/:id/video/start` y `/stop`; MCP; `simctl io recordVideo`. |
| Listar apps instaladas | Implementado | Sí | No | `GET /session/:id/apps` y MCP `cuyscout_list_apps`; `simctl list apps --json`. |
| Keychain | Implementado | Sí | No | `POST /session/:id/keychain` y MCP `cuyscout_reset_keychain`; `simctl keychain reset`. |
| Deep links | Implementado | Sí | No | `POST /session/:id/deep-link` y MCP `cuyscout_deep_link`; `simctl openurl` con esquema personalizado. |
| Push notifications | Implementado | Sí | No | `POST /session/:id/push-notification` y MCP `cuyscout_push_notification`; `simctl push` con fixture `.apns`. |
| Content size | Implementado | Sí | No | `POST /session/:id/content-size` y MCP `cuyscout_set_content_size`; `simctl ui content_size`. |
| Add media | Implementado | Sí | No | `POST /session/:id/add-media` y MCP `cuyscout_add_media`; `simctl addmedia` para fotos/videos. |
| Spawn de procesos | Implementado | Sí | No | `POST /session/:id/spawn` y MCP `cuyscout_spawn`; `simctl spawn` con args. |
| iCloud sync | Implementado | Sí | No | `POST /session/:id/icloud-sync` y MCP `cuyscout_icloud_sync`; `simctl icloud sync`. |
| Element location | Implementado | Sí | Sí | `GET /element/:eid/location` y MCP `cuyscout_element_location`; deriva x, y, centerX, centerY de `elementRect`. |
| Element size | Implementado | Sí | Sí | `GET /element/:eid/size` y MCP `cuyscout_element_size`; deriva width, height de `elementRect`. |
| Shake | Implementado | Sí | No | `POST /session/:id/shake` y MCP `cuyscout_shake`; `simctl ui shake`. |
| Double tap | Implementado | Sí | No | `POST /element/:eid/doubletap` y MCP `cuyscout_double_tap`; Native vía bridge. |
| Long press | Implementado | Sí | No | `POST /element/:eid/longpress` y MCP `cuyscout_long_press`; Native vía bridge con duración configurable. |
| Pinch/zoom | Implementado | Sí | No | Acción `pinch(scale,velocity)` vía bridge; HTTP/MCP pendiente. |
| Get appearance | Implementado | Sí | No | `GET /session/:id/appearance` y MCP `cuyscout_get_appearance`; trackea último valor establecido. |
| Get content size | Implementado | Sí | No | `GET /session/:id/content-size` y MCP `cuyscout_get_content_size`; trackea último valor establecido. |
| Enumerate files | Implementado | Sí | No | `POST /session/:id/enumerate` y MCP `cuyscout_enumerate_files`; `simctl io enumerate`. |
| Lifecycle de simulador | Implementado | Sí | No | `POST /devices/boot`, `/shutdown`, `/erase`, `/clone`, `/create`, `/rename`, `DELETE /devices/:id` y MCP; `simctl boot/shutdown/erase/clone/delete/create/rename`. |
| Pinch/zoom | Implementado | Sí | No | `POST /element/:eid/pinch` y MCP `cuyscout_pinch`; Native vía bridge con scale y velocity. |
| Photo library sync | Implementado | Sí | No | `POST /session/:id/pbsync` y MCP `cuyscout_pbsync`; `simctl pbsync`. |
| Device info enriquecido | Implementado | Sí | Sí | `deviceInfo` ahora incluye `bundleIdentifier`, `automationName`, `manufacturer`, `deviceName`, `platformVersion`. |
| Transferencia de archivos | Implementado | Sí | No | `POST /session/:id/download` y `/upload` y MCP; `simctl io download/upload`. |
| App container | Implementado | Sí | No | `GET /session/:id/app-container` y MCP `cuyscout_get_app_container`; `simctl get_app_container`. |
| Configuración del simulador | Implementado | Sí | No | `GET/POST /session/:id/config` y MCP `cuyscout_get_config`/`cuyscout_set_config`; `simctl config get/set`. |
| Verificación de pruebas | Implementado | Sí | Sí | `POST /session/:id/verify-test` y MCP `cuyscout_verify_test_plan`; compila, ejecuta desde estado limpio y reporta resultado. |
| Clasificación de fallos | Implementado | Sí | Sí | `FailureCategory` enum (product/selector/synchronization/environment/data/infrastructure) y `classifyFailure` por MCP/HTTP. |
| Overlay de accesibilidad | Implementado | Sí | Sí | `GET /session/:id/accessibility-overlay` y MCP; screenshot + elementos accesibles para inspector visual. |
| Comparación visual por región | Implementado | Sí | Sí | `POST /session/:id/visual-compare-region` y MCP; compara región específica con tolerancia. |
| Política de seguridad de plugins | Implementado | Sí | Sí | `PluginSecurityPolicy` con `requireSignature`, `allowedCapabilities` y `deniedActions`; `POST /plugins/security-policy` y MCP. |
| TLS handshake real | Implementado | Sí | Sí | `Network.framework` con `NWProtocolTLS`; `CUYSCOUT_TLS_CERT`/`CUYSCOUT_TLS_KEY` cargan identidad del Keychain. |
| Capabilities exhaustivas | Implementado | Sí | Sí | `app`, `noReset`, `fullReset`, `browserName`, `xcodeOrgId`, `xcodeSigningId`, `wdaLocalPort` validados en `CapabilityNegotiator`. |

## Validación pendiente

- Ejecutar clientes oficiales Appium Python, Java y WebdriverIO contra un simulador real.
- Integrar una aplicación híbrida real con WebKit Inspector.
- Añadir pruebas de conformidad automatizadas para cada ruta de la tabla.
- `Tests/Conformance/w3c_smoke.sh` cubre el flujo HTTP básico; falta ejecutarlo contra un simulador real y añadir clientes oficiales.
- `appium_python_smoke.py` y `webdriverio_smoke.mjs` cubren creación de sesión y capabilities con clientes oficiales cuando sus dependencias están instaladas.
- `Tests/Conformance/requirements.txt`, `package.json` y `README.md` documentan la instalación y ejecución reproducible de ambos clientes.
- `.github/workflows/conformance.yml` automatiza la ejecución en macOS con simulador y conserva logs para diagnóstico.
- Implementar WebSocket/BiDi push y captura DOM visual.
- Búsqueda relativa Native requiere ejecutarse contra un runner XCTest real con `findElementFromElement`/`findElementsFromElement`.
