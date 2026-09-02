# CuyScout — Roadmap hacia una plataforma de automatización agent-first

## Visión

CuyScout será una plataforma de automatización de interfaces que permita a agentes explorar una aplicación, comprender su estado, detectar rutas y riesgos, producir pruebas reproducibles y mantenerlas con el menor consumo posible de tokens.

El objetivo no es copiar Appium función por función. CuyScout debe:

1. Alcanzar compatibilidad con el protocolo y ecosistema de Appium donde aporte interoperabilidad.
2. Superarlo en exploración autónoma, representación semántica, eficiencia para agentes, generación de pruebas y autocorrección.
3. Empezar con una experiencia excelente en iOS y extenderse mediante drivers.

## Estado actual

CuyScout ya dispone de una base funcional en Swift con:

- Servidor HTTP local y sesiones.
- Descubrimiento y control básico de simuladores mediante `simctl`.
- Puente XCTest/XCUITest para acciones de interfaz.
- Tap, swipe, escritura, screenshots y control de aplicaciones.
- Búsqueda semántica por identificador, label, value, tipo y predicate.
- Árbol de accesibilidad completo, compacto y diferencial.
- Waits, assertions y secuencias de acciones.
- Grabación de sesiones y generación de pruebas XCTest.
- Exportación Appium para JavaScript/WebdriverIO y Python.
- Servidor MCP para agentes.
- Exploración con límites de tiempo, acciones y detección inicial de bucles.

La base todavía es experimental: el servidor HTTP es mínimo, el runner XCTest requiere integración manual y la API no es compatible por completo con W3C WebDriver.

## Progreso de implementación

**Actualizado:** 2026-08-11

- Fase 0: iniciada. El paquete compila y cuenta con pruebas unitarias para acciones, grabaciones y exportadores.
- Fase 1: iniciada. Ya existe una primera capa W3C para capabilities de sesión, referencias de elementos, `findElement`, `findElements`, click, escritura, texto y `source`.
- Fase 1: capabilities negociadas expuestas también en `GET /session/:id/capabilities`, incluyendo el driver asociado.
- Fase 1: capabilities negociadas disponibles también por MCP mediante `cuyscout_session_capabilities`, con aliases W3C/Appium y puerto de automatización.
- Fase 1: snapshot machine-readable de conformidad disponible por HTTP (`/conformance`) y MCP (`cuyscout_conformance`) para agentes y CI.
- Fase 1: negociación W3C de capabilities completa para `alwaysMatch`/`firstMatch`, con detección de conflictos y errores estructurados de combinación incompatible.
- Fase 1: `CapabilityNegotiator` extraído al núcleo, con aliases W3C/Appium normalizados y pruebas unitarias independientes del servidor HTTP.
- Fase 1: compatibilidad de enrutamiento con `/wd/hub` además de la raíz W3C, para clientes Appium que conservan el prefijo tradicional.
- Fase 0: snapshot de conformidad cubierto por round-trip automatizado para preservar su contrato JSON.
- Fase 1: prueba de humo W3C reproducible añadida para status, conformance, creación de sesión, capabilities y timeouts; la ejecución contra clientes oficiales requiere instalarlos.
- Fase 1: smoke tests preparados para Appium Python y WebdriverIO, pendientes únicamente de ejecución en un entorno con sus dependencias y simulador.
- Fase 1: dependencias y guía reproducible declaradas para ejecutar los smoke tests oficiales en CI o una máquina con simulador.
- Fase 1: workflow manual de conformance automatiza simulador, gateway, clientes oficiales y artifact de logs.
- Fase 1: corregido el enrutamiento de acciones semánticas nativas al puente XCTest, incluyendo búsquedas, interacción, waits y assertions.
- Fase 1: errores de elementos alineados con W3C; una búsqueda sin coincidencia devuelve `no such element`/404.
- Fase 1: búsqueda relativa W3C implementada para WebView con selectores CSS mediante `/element/:id/element` y `/elements`.
- Fase 1: búsqueda relativa WebView disponible también por MCP con referencias compactas de elementos.
- Fase 1: referencias inválidas alineadas con W3C; IDs desconocidos devuelven `stale element reference`/404.
- Fase 3: iniciada. Existe observación compacta `cuyscout_observe`/`/observe` con `stateId`, cambio de pantalla, acciones sugeridas y estado de exploración.
- Fase 3: estado agregado implementado con `cuyscout_agent_state`/`/agent-state`; combina observación, métricas, eventos recientes y señal de bucle en una sola llamada.
- Fase 3: ejecución batch implementada con `cuyscout_execute_batch`/`/batch`, con fallo indexado, parada segura y reparación resiliente opcional.
- Fase 3: batches idempotentes mediante `requestId`, con caché acotada por sesión para evitar acciones duplicadas durante reintentos de agentes.
- Fase 3: batches protegidos con límite temporal de hasta 120 segundos y error `batch_timeout` indexado.
- Fase 3: cancelación explícita de batches por `requestId` mediante MCP/HTTP, efectiva entre acciones y compatible con idempotencia.
- Fase 8: los pasos fallidos de batches incluyen categoría operativa para separar reintentos de infraestructura de fallos de producto.
- Fase 8: batches soportan reintentos acotados exclusivamente para fallos `infrastructure`, separados de selector y producto.
- Fase 0: contrato JSON de categorías de fallo cubierto por prueba automatizada para preservar reintentos selectivos.
- Fase 0: contrato automatizado de cancelación de batches cubierto por pruebas unitarias para preservar el estado `batch_cancelled`.
- Fase 3: validación previa de batches con errores estructurales y advertencias de placeholders.
- Fase 3: cobertura compacta de exploración con estados, transiciones únicas, repeticiones y riesgo de bucle.
- Fase 3: `cuyscout_agent_state` incluye cobertura directamente para evitar una llamada adicional del agente.
- Fase 3: el estado del agente incluye preparación de sesión y bloqueos explícitos del puente XCTest/WebView.
- Fase 3: el estado agregado tolera sesiones sin puente y devuelve bloqueos accionables en lugar de generar errores repetibles.
- Fase 3: identidad estable de pantalla; normaliza timestamps, UUIDs y contadores dinámicos antes de detectar cambios, transiciones repetidas y bucles.
- Fase 3: acciones disponibles expuestas explícitamente como `cuyscout_available_actions` y `GET /session/:id/available-actions`, reutilizando selectores semánticos y marcadores `<text>` para reducir decisiones repetidas del agente.
- Fase 4: al detener una grabación se persiste automáticamente el artefacto versionado para conservar pasos y diagnósticos sin una exportación manual.
- Fase 4: política opcional de presupuesto máximo de comandos por sesión para cortar exploraciones infinitas fuera del modo exploration.
- Fase 4: el presupuesto restante se expone preventivamente en `agent-state` para que el agente cierre o cambie de estrategia antes del bloqueo.
- Fase 4: contador de comandos independiente de la retención de eventos para que los límites no se reinicien al purgar historial.
- Fase 4: el contador total de comandos se conserva en artefactos para mantener límites al restaurar sesiones.
- Fase 4: la política de seguridad completa se conserva y restaura junto con la sesión.
- Fase 9: denylist de acciones por sesión mediante `deniedActionTypes`, conservada en artefactos y aplicada también a replay/checkpoints.
- Fase 9: denylist recursiva para impedir acciones bloqueadas dentro de secuencias y batches.
- Fase 9: auditoría de decisiones de seguridad por sesión, persistida en artefactos y disponible por HTTP/MCP.
- Fase 9: scopes Bearer `read`, `execute` y `admin` configurables mediante `CUYSCOUT_TOKEN_SCOPES`.
- Fase 9: logs JSON de solicitudes HTTP configurables mediante `CUYSCOUT_LOG_FORMAT=json`, sin payloads sensibles.
- Fase 9: logs JSON enriquecidos con `trace_id` y `duration_ms` para correlación y diagnóstico de latencia.
- Fase 9: retención configurable de artefactos mediante `CUYSCOUT_ARTIFACT_RETENTION`; `0` conserva todos.
- Fase 9: endpoint de métricas Prometheus implementado en `/metrics?format=prometheus`.
- Fase 9: configuración `.cuyscout.yaml` implementada con precedence segura de variables de entorno y schema JSON versionable.
- Fase 8: dirección de escucha configurable para workers de device farm, manteniendo bind local por defecto.
- Fase 9: bind remoto protegido: las interfaces no locales requieren autenticación Bearer antes de iniciar.
- Fase 9: perfiles `local`, `ci` y `device-farm` aplican defaults operativos seguros; las variables explícitas siempre prevalecen.
- Fase 9: la configuración se valida al arranque contra rangos y enums del schema, evitando defaults silenciosos para valores inválidos.
- Fase 4: replay y restauración consumen el presupuesto de comandos incluso cuando no generan eventos normales.
- Fase 4: eliminación completa del estado de seguridad y presupuesto al cerrar sesiones.
- Fase 4: consulta ultracompacta `cuyscout_session_readiness`/`/readiness` para comprobar infraestructura sin descargar el estado de pantalla.
- Fase 4: resumen `cuyscout_session_health`/`/health` combina readiness, bloqueos, presupuesto y métricas para reducir llamadas de decisión del agente.
- Fase 3: memoria persistente de lecciones aprendidas globales, por proyecto y por sesión; `agent-state` incorpora contexto compacto para reutilizar aprendizajes entre pruebas.
- Fase 0: round-trip automatizado confirma persistencia de lecciones entre instancias del almacén.
- Fase 3: consolidación automática de lecciones duplicadas, refuerzo por recurrencia y búsqueda compacta por texto/tags para limitar tokens.
- Fase 3: aprendizaje automático al finalizar exploraciones y bajo demanda por MCP/HTTP; infiere únicamente patrones respaldados por fallos repetidos, ciclos, latencias o escritura seguida de controles inaccesibles, sin copiar datos introducidos.
- Fase 3: `agent-state` usa las lecciones aplicables para producir un `nextActionHint` contextual y accionable, reduciendo decisiones repetidas del agente.
- Fase 3: recuperación contextual de lecciones; `agent-state` prioriza aprendizajes por señales recientes de teclado, selectores, latencia y bucles, manteniendo la respuesta compacta.
- Fase 4: validador centralizado de planes antes de exportar; detecta pasos fallidos, selectores frágiles, coordenadas, placeholders, datos sensibles y exportaciones vacías, comprobando los formatos generados reales.
- Fase 4: exportador TypeScript real para WebdriverIO con tipos `WebdriverIO.Browser` y `WebdriverIO.Element`, separado del exportador JavaScript.
- Fase 4: validador de estructura para todos los exportadores; comprueba marcadores de lenguaje y JSON portable antes de declarar el plan exportable.
- Fase 3/7: recursos MCP de solo lectura para estado compacto, lecciones y reportes, con URIs estables para reducir polling y llamadas de herramientas.
- Fase 3/7: prompt MCP reutilizable `cuyscout_explore_to_test` para estandarizar exploración, aprendizaje, validación, replay y exportación con contexto compacto.
- Fase 3/8: resumen compacto de batches por MCP/HTTP con categorías, pasos fallidos y siguiente acción, sin descargar resultados completos.
- Fase 7/10: recursos MCP incrementales para eventos por cursor y resumen de batch, acercando la observación reactiva sin exigir WebSocket BiDi.
- Fase 0: contrato JSON del resumen de salud cubierto por round-trip automatizado.
- Fase 4: autosave periódico configurable mediante `CUYSCOUT_AUTOSAVE_INTERVAL` para reducir pérdida de exploraciones activas.
- Fase 4: estado compacto del almacén de artefactos para diagnosticar persistencia sin descargar paquetes.
- Fase 4: el estado de persistencia incluye tamaño total y fecha del último snapshot.
- Fase 4: recuperación agent-first que recomienda ejecución resiliente después de un comando fallido.
- Fase 4: recomendaciones de recuperación priorizan bloqueos de infraestructura antes de proponer nuevas acciones.
- Fase 4: `agent-state` soporta modo `lightweight` sin lectura de accesibilidad para polling de bajo costo.
- Fase 4: ejecución batch protegida por validación estructural automática antes de ejecutar acciones.
- Fase 4: replay y checkpoint restore respetan políticas de seguridad, incluido el control de lifecycle de `resetApp`.
- Fase 4: recomendación automática de `accessibilityDiff` cuando el estado de pantalla no cambia.
- Fase 4: contratos versionados de pantalla implementados con generación y comparación de elementos accesibles.
- Fase 3: grafo y checkpoints implementados. Existen `cuyscout_navigation_graph`, `cuyscout_create_checkpoint`, `cuyscout_list_checkpoints` y cobertura compacta por transición; la restauración física verificable depende del runner XCTest/WebView real.
- Fase 3: restauración lógica implementada. `cuyscout_restore_checkpoint` reproduce los pasos hasta un checkpoint y puede intentar resetear la app antes del replay, respetando `SecurityPolicy`.
- Fase 4: iniciada. Existe `TestPlan` normalizado con pasos, duraciones y warnings antes de exportar código.
- Fase 4: validación iniciada. `cuyscout_validate_test_plan` y `/recording/plan/validate` detectan errores y warnings antes de exportar.
- Fase 4: minimización agent-first. `cuyscout_get_optimized_test_plan` y `/recording/plan/optimized` compactan observaciones y duplicados sin ocultar qué se eliminó.
- Fase 4: exportación ampliada. Añadidos Gherkin y JSON portable además de XCTest, WebdriverIO y Python.
- Fase 4: interoperabilidad ampliada. Añadido exportador Appium Java/JUnit por MCP y HTTP.
- Fase 4: exportación TypeScript compatible con WebdriverIO añadida por MCP y HTTP.
- Fase 5: iniciada. `cuyscout_repair_selector` y `/selector/repairs` proponen alternativas semánticas con score y explicación.
- Fase 5: ejecución autocurable. `cuyscout_execute_resilient` reintenta selectores rotos solo cuando existe una alternativa semántica confiable.
- Fase 5: autocuración HTTP disponible con `POST /session/:id/actions?repair=true`, además del MCP.
- Fase 5: errores de elementos WebView normalizados a `no such element` para compartir autocuración con Native.
- Fase 5: reparación WebView ampliada con candidatos CSS derivados de id, name, aria-label y texto DOM.
- Fase 5: autocuración granular dentro de secuencias, reparando solo el paso semántico que falla.
- Fase 5: propuestas de reparación de acciones con original/propuesta/score/motivo y aprobación explícita antes de convertirlas en un cambio de prueba.
- Fase 5: auditoría persistente de reparaciones propuestas, aplicadas y rechazadas, incluida en artifacts y consultable por MCP/HTTP.
- Fase 9: redacción de datos sensibles aplicada también a las acciones contenidas en la auditoría de autocuración de los artifacts.
- Fase 9: redacción automática de emails, tokens, contraseñas, api keys y números largos en lecciones antes de persistirlas.
- Accesibilidad: auditoría inicial implementada por MCP y HTTP para identifiers, labels, ambigüedad y hit targets.
- Accesibilidad híbrida: la auditoría también analiza controles DOM en WEBVIEW sin requerir el bridge XCTest.
- Accesibilidad agent-first: detener una exploración adjunta automáticamente la auditoría de la pantalla final al resultado.
- Persistencia de accesibilidad: la auditoría final se guarda y restaura dentro del artefacto de sesión.
- Fase 0: round-trip automatizado confirma que la auditoría de accesibilidad persiste en artefactos versionados.
- Inspector agent-first: reporte agregado implementado con `cuyscout_session_report` y `/session/:id/report`.
- Inspector agent-first: el reporte conserva el conteo de pasos después de detener una grabación.
- Inspector HTML: reporte autocontenido implementado en `/session/:id/report.html` y MCP `cuyscout_export_report_html`.
- SDK de drivers: iniciado con `CuyScoutDriver`, `DriverRegistry`, health checks y adaptador de simulador iOS.
- SDK de drivers: el motor enruta acciones de control por el driver asociado a la sesión, seleccionable por capability `appium:driverId` o MCP; queda pendiente carga dinámica.
- SDK de plugins: iniciado con `CuyScoutPlugin`, `PluginRegistry` y hooks before/after de comandos.
- SDK de plugins: registro y retiro públicos desde `ScoutEngine` para integraciones Swift; queda pendiente carga dinámica de módulos externos.
- Seguridad operativa: iniciada con `SecurityPolicy` por sesión y controles para lifecycle, clipboard, coordenadas y URLs externas.
- Escala inicial: el gateway HTTP atiende conexiones concurrentemente; aún falta scheduler, aislamiento de puertos y device farm.
- Escala inicial: el scheduler asigna un puerto de automatización exclusivo por sesión (`CUYSCOUT_PORT_START`/`CUYSCOUT_PORT_COUNT`) y lo libera al cerrar la sesión.
- Fase 0: aislamiento de puertos cubierto por prueba automatizada de asignación, diferenciación y reutilización segura.
- Scheduler inicial: implementado con leases por dispositivo, liberación al cerrar sesión y estado HTTP/MCP.
- Scheduler agent-first: creación de sesión admite espera acotada por disponibilidad, evitando loops de polling en clientes.
- Capabilities seguras: el driver seleccionado se valida contra la plataforma del dispositivo antes de confirmar el lease.
- Autenticación inicial: token Bearer opcional mediante `CUYSCOUT_TOKEN`; health checks públicos.
- Eventos/BiDi inicial: canal de polling HTTP/MCP con eventos compactos de comandos y duración.
- Eventos diagnósticos: los eventos de fallo incluyen el error serializado para que los agentes puedan decidir una reparación con una sola lectura.
- Eventos eficientes: long-polling MCP/HTTP para esperar eventos nuevos sin bucles de consultas del agente; timeout máximo de 30 segundos.
- Eventos reactivos iniciales: stream SSE acotado en `/session/:id/events/stream` entrega eventos sin polling repetido; las suscripciones BiDi completas siguen pendientes.
- Retención operativa: `CUYSCOUT_EVENT_RETENTION` permite ajustar memoria e historial entre 10 y 10000 eventos.
- Métricas globales: `cuyscout_fleet_metrics` y `/metrics` resumen salud del gateway sin consultar sesión por sesión.
- Observabilidad agent-first: `cuyscout_metrics` y `/session/:id/metrics` resumen tasa de fallos, latencia promedio, p95 y distribución de acciones sin transferir todo el historial.
- Artefactos portables: `cuyscout_export_artifacts` y `/session/:id/artifacts` generan un paquete versionado para persistencia externa y auditoría. `cuyscout_restore_artifacts` y `POST /session/restore` rehidratan de forma segura eventos, checkpoints y grabaciones cuando el dispositivo sigue disponible.
- Persistencia local: los artefactos se guardan automáticamente mediante `ArtifactStore`, con directorio configurable por `CUYSCOUT_ARTIFACT_DIR`, listado y restauración por ID.
- Persistencia local: el directorio predeterminado usa `Application Support/CuyScout/artifacts`, evitando depender de almacenamiento temporal entre reinicios.
- Persistencia agent-first: catálogo compacto de artefactos mediante `GET /artifacts/catalog` y MCP `cuyscout_artifact_catalog`, con metadatos de sesión, dispositivo, driver, pasos y URL para seleccionar restauraciones sin descargar JSON completo.
- Restauración segura agent-first: preflight de artefactos mediante `POST /session/restore/validate` y MCP `cuyscout_validate_restore`, que valida esquema, driver, dispositivo, lease y conflicto de sesión antes de restaurar.
- Scheduler resiliente: leases con heartbeat y expiración configurable mediante `CUYSCOUT_LEASE_TTL_SECONDS`; `perform` renueva el lease y el estado HTTP/MCP expone expiración para evitar simuladores bloqueados por agentes desconectados.
- Scheduler agent-first: heartbeat explícito mediante `POST /session/:id/heartbeat` y MCP `cuyscout_heartbeat`, para mantener sesiones vivas durante análisis sin ejecutar acciones artificiales.
- Exploración agent-first: las acciones sugeridas se ordenan por novedad contra el grafo de navegación y las rutas no cubiertas llevan un motivo explícito para guiar al agente hacia cobertura nueva.
- Exploración agent-first: las sugerencias incluyen riesgo `low`, `medium` o `high`; priorizan rutas nuevas de bajo riesgo y marcan controles destructivos o campos sensibles sin ejecutarlos automáticamente.
- Persistencia de contexto: los artefactos incluyen y restauran URL actual y grafo de navegación además de pasos y checkpoints.
- Persistencia de grabación: la última grabación se conserva en el artefacto incluso después de `stopRecording` o `stopExploration`.
- Seguridad de artefactos: textos introducidos, clipboard y valores esperados se redactan por defecto; se puede desactivar explícitamente por entorno.
- Seguridad de compilación: la validación marca placeholders `<redacted>` para impedir exportaciones aparentemente ejecutables pero incompletas.
- Parametrización segura: replay acepta variables efímeras para resolver `<redacted>` y `<text>` sin persistir sus valores.
- Replay resiliente: la verificación puede activar autocuración de selectores durante la reproducción.
- Continuidad de compilación: plan y exportadores pueden consultarse después de detener la grabación usando el último snapshot disponible.
- Verificación de pruebas: `cuyscout_replay_recording` y `/recording/replay` reproducen la grabación sin regrabar y reportan el primer fallo.
- Integración CI: replay exportable como JUnit XML por MCP y HTTP.
- Integración CI inicial: workflow de GitHub Actions para pruebas paralelas y compilación release en macOS.
- Restauración segura: la validación del driver ocurre antes de adquirir el lease del simulador, evitando reservas huérfanas ante artefactos incompatibles.
- W3C screenshot de elemento: implementado para Native/XCUITest; WebView queda pendiente.
- W3C screenshot de elemento: corregido el enrutamiento del motor al bridge XCTest; WebView queda pendiente.
- W3C screenshot de elemento: WebView captura `<canvas>` e `<img>` como PNG mediante JavaScript; queda pendiente el DOM HTML general vía WebKit Inspector.
- W3C screenshot de elemento: WebView captura también elementos HTML generales recortando la captura real del dispositivo según `getBoundingClientRect` y `devicePixelRatio`; el uso de WebKit Inspector sigue pendiente para captura nativa del viewport.
- W3C alertas: lectura compacta de texto y botones disponible mediante `GET /session/:id/alert/text` y MCP `cuyscout_get_alert_text`, reutilizando el árbol XCTest sin transferirlo completo al agente.
- Appium mobile methods: `mobile: getDeviceInfo`, `mobile: getDeviceTime`, `mobile: getPasteboard` y `mobile: setPasteboard` disponibles por execute, con el clipboard sujeto a `SecurityPolicy`; la información también se expone por MCP.
- W3C implicit timeout: aplicado a búsquedas nativas y WebView.
- W3C script timeout: aplicado a la cola de ejecución JavaScript WebView.
- W3C timeouts: consulta y actualización disponibles tanto por HTTP como por MCP, con validación de claves y valores.
- Diagnóstico inicial: implementado por HTTP (`GET /doctor`) y MCP (`cuyscout_doctor`) para comprobar dependencias críticas y opcionales.
- Salud del puente XCTest: implementada por HTTP (`/bridge/status`) y MCP (`cuyscout_xctest_status`) con actividad y comandos pendientes.
- Orientación: implementada con `GET/POST /session/:id/rotation` para simulador y runner XCTest.
- Clipboard: implementado con endpoints Appium y `UIPasteboard` en el runner XCTest.
- Lifecycle de simulador: implementados install, remove y reset de aplicaciones por HTTP/MCP.
- Lifecycle de sesión: implementados activate y terminate de aplicaciones por HTTP/MCP.
- Background/foreground: implementado `background_app` con Home y espera configurable en XCTest.
- Pendiente inmediato: capabilities exhaustivas y pruebas de conformidad con clientes Python/WebdriverIO. La capa W3C ya permite consultar sesiones y capabilities negociadas, navegación `back/forward/refresh` con `pageLoad` timeout, `title`, `source`, `page-info`, alertas con entrada de texto, `findElements` con referencias múltiples, búsqueda relativa Native y WebView, elementos con `enabled`/`rect`/`selected`/`name`/`property`, `window/rect`, `element/active`, `cookie`, `scroll`, permisos, biometría, geolocalización, visual diff, timeline, cola de sesiones, dashboard de flota, caché de apps, logs de consola y reglas reactivas. El MCP propone acciones a partir de accesibilidad XCTest o del DOM WebView para acelerar exploraciones. La capa semántica WebView soporta contextos `WEBVIEW_*`, ejecución JavaScript, selectores CSS/XPath, referencias de elementos, click, escritura, limpieza, visibilidad, texto, atributos, propiedades, estado y polling por HTTP/MCP. Falta conectar WebKit Inspector/iOS real y validar con una app híbrida.
- Fase 2: parcialmente iniciada con acciones semánticas, waits, assertions, accesibilidad diferencial y control de lifecycle.
- Fase 1: búsqueda relativa Native implementada mediante `findElementFromElement`/`findElementsFromElement` vía puente XCTest, con soporte para cualquier estrategia semántica además de CSS WebView.
- Fase 1: búsqueda relativa por MCP ampliada con `strategy` para soportar Native y WebView, no solo CSS.
- Fase 1: window rect W3C implementado con `GET/POST /session/:id/window/rect` y MCP `cuyscout_window_rect`/`cuyscout_set_window_rect`; Native usa dimensiones del screenshot y WebView usa `window.innerWidth/innerHeight`.
- Fase 1: propiedades W3C `selected` y `name` de elementos implementadas por HTTP (`/element/:eid/selected`, `/element/:eid/name`) y MCP (`cuyscout_element_selected`, `cuyscout_element_name`).
- Fase 1: timeout `pageLoad` aplicado a navegación WebView (`back`, `forward`, `refresh`, `openURL`) esperando `document.readyState == complete`.
- Fase 1: elemento activo W3C implementado con `GET /session/:id/element/active` y MCP `cuyscout_active_element`; Native devuelve nil, WebView usa `document.activeElement`.
- Fase 1: propiedades W3C de elemento implementadas con `GET /element/:eid/property/:name` y MCP `cuyscout_element_property`, complementando los atributos existentes.
- Fase 1: gestión de cookies W3C implementada con `GET/POST/DELETE /session/:id/cookie` y MCP `cuyscout_get_cookies`/`cuyscout_add_cookie`/`cuyscout_delete_cookie`/`cuyscout_delete_all_cookies`; WebView usa `document.cookie`.
- Fase 1: entrada de texto en alertas implementada con `POST /session/:id/alert/text` y MCP `cuyscout_set_alert_text`; Native vía puente XCTest.
- Fase 1: scroll W3C implementado; el source `wheel` en W3C Actions produce `scroll(x,y)`, disponible también por HTTP/MCP `cuyscout_scroll`; WebView usa `window.scrollBy`, Native vía puente.
- Fase 0: 7 pruebas automatizadas añadidas para scroll, alert text, element property, cookies, active element y conformidad.
- Fase 2: permisos de app implementados con `POST /session/:id/appium/permissions` y MCP `cuyscout_grant_permission`; usa `simctl privacy grant` para camera, contacts, location, photos, microphone, etc.
- Fase 2: biometría simulada implementada con `POST /session/:id/biometry` y MCP `cuyscout_set_biometry`; usa `simctl biometry enable/disable`.
- Fase 2: geolocalización simulada implementada con `POST /session/:id/geolocation` y MCP `cuyscout_set_location`; usa `simctl location set`.
- Fase 6: visual diff con tolerancia implementado con `POST /session/:id/visual-diff` y MCP `cuyscout_visual_diff`; compara screenshots pixel a pixel y devuelve `differenceRatio`, `pixelDifferences` e `identical`.
- Fase 6: timeline de acciones implementado con `GET /session/:id/timeline` y MCP `cuyscout_timeline`; devuelve entradas con acción, duración, éxito/error y screenshots opcionales.
- Fase 7: plugin allowlist implementado mediante `PluginRegistry.setAllowlist`; filtra plugins no autorizados antes del registro.
- Fase 7: driver capabilities declarativas implementadas; `DriverDescriptor` ahora declara `supportedCapabilities` y `supportedSettings` por driver.
- Fase 0: 11 pruebas automatizadas añadidas para permisos, biometría, geolocalización, visual diff, timeline, plugin allowlist y driver capabilities.
- Fase 8: cola de sesiones con prioridades implementada mediante `POST /scheduler/queue` y MCP `cuyscout_enqueue_session`; ordena por prioridad low/normal/high/urgent y permite cancelación.
- Fase 8: dashboard de flota implementado con `GET /dashboard` y MCP `cuyscout_fleet_dashboard`; resume sesiones activas, cola, dispositivos leased/available, eventos y tasa de fallo.
- Fase 8: caché de aplicaciones implementado con `POST /app-cache` y MCP `cuyscout_cache_app`; reutiliza rutas cacheadas en `installApp` para acelerar despliegue.
- Fase 9: TLS configurable implementado mediante `CUYSCOUT_TLS_CERT`/`CUYSCOUT_TLS_KEY` y `.cuyscout.yaml` `server.tls`; validación al arranque verifica existencia de cert y key.
- Fase 10: captura de logs de consola implementada con `GET/POST /session/:id/console` y MCP `cuyscout_console_logs`/`cuyscout_record_console_log`; retención configurable.
- Fase 10: reglas reactivas implementadas con `GET/POST/DELETE /session/:id/reactive-rules` y MCP; ejecuta una acción automáticamente cuando ocurre un evento coincidente.
- Fase 0: 12 pruebas automatizadas añadidas para cola de sesiones, dashboard, caché, logs de consola, reglas reactivas y TLS.
- Fase 5: fingerprints semánticos implementados con `GET/POST /session/:id/fingerprints` y MCP `cuyscout_record_fingerprint`/`cuyscout_fingerprints`/`cuyscout_match_fingerprint`; registra identifier, label, tipo, frame y hash para autocuración.
- Fase 5: comparación de comportamiento implementada con `POST /session/:id/behavior-compare` y MCP `cuyscout_compare_behavior`; detecta diferencias entre éxito esperado y observado.
- Fase 7: plugins con endpoints HTTP custom implementados; `CuyScoutPlugin` ahora soporta `routes()`, `handleRoute()` y `transformResult()`; `GET /plugins/routes` lista rutas registradas.
- Fase 7: carga dinámica de drivers implementada con `GET/POST /drivers/manifests` y MCP; `DriverRegistry.loadDriverFromManifest` usa `Bundle.load` para cargar drivers externos.
- Fase 9: TLS aplicado al servidor; `main.swift` pasa `CUYSCOUT_TLS_CERT`/`CUYSCOUT_TLS_KEY` al `ScoutHTTPServer`; el esquema cambia a `https` cuando TLS está configurado.
- Fase 0: 11 pruebas automatizadas añadidas para fingerprints, behavior comparison, driver manifests, plugin routes y transformación de resultados.
- Fase 1: submit de elemento W3C implementado con `POST /element/:eid/submit` y acción `submit`; Native vía puente XCTest.
- Fase 1: W3C Actions soporta `pause` (duración en ms) y `pointerMove` con `origin` de elemento (resuelve rect y offset).
- Fase 4: replay con `resetApp` implementado; termina y relanza la app antes de reproducir pasos desde estado limpio.
- Fase 5: fingerprints semánticos integrados en `repairSelector`; busca coincidencias registradas previamente antes de escanear el árbol.
- Fase 7: firma de plugins implementada; `PluginDescriptor.signature` opcional para validación de integridad.
- Fase 8: sharding implementado con `GET/POST /session/:id/shard` y MCP; distribuye pasos por `shardIndex`/`shardCount`.
- Fase 9: OpenTelemetry implementado con `GET/POST /session/:id/otel` y MCP; registra spans con `traceID`, `spanID` y `parentSpanID`.
- Fase 10: captura de tráfico de red implementada con `GET/POST /session/:id/network` y MCP; retención configurable.
- Fase 0: 12 pruebas automatizadas añadidas para submit, network, sharding, OpenTelemetry, plugin signature y replay resetApp.
- Fase 2: apariencia (dark/light) implementada con `POST /session/:id/appearance` y MCP `cuyscout_set_appearance`; usa `simctl ui appearance`.
- Fase 2: barra de estado implementada con `POST /session/:id/status-bar` y MCP `cuyscout_set_status_bar`; usa `simctl status_bar override` para time, dataNetwork, wifiMode, batteryLevel, batteryState.
- Fase 2: grabación de video implementada con `POST /session/:id/video/start` y `/stop` más MCP; usa `simctl io recordVideo`.
- Fase 2: listado de apps instaladas implementado con `GET /session/:id/apps` y MCP `cuyscout_list_apps`; usa `simctl list apps --json`.
- Fase 2: keychain reset implementado con `POST /session/:id/keychain` y MCP `cuyscout_reset_keychain`; usa `simctl keychain reset`.
- Fase 2: deep links implementados con `POST /session/:id/deep-link` y MCP `cuyscout_deep_link`; usa `simctl openurl` con esquema personalizado.
- Fase 1: mobile methods ampliados con `mobile: installApp`, `mobile: removeApp`, `mobile: activateApp`, `mobile: listApps`, `mobile: setAppearance`, `mobile: deepLink`, `mobile: resetKeychain`.
- Fase 0: 9 pruebas automatizadas añadidas para apariencia, status bar, video, apps, keychain y deep links.
- Fase 2: push notifications implementadas con `POST /session/:id/push-notification` y MCP `cuyscout_push_notification`; usa `simctl push` con fixture `.apns`.
- Fase 2: content size implementado con `POST /session/:id/content-size` y MCP `cuyscout_set_content_size`; usa `simctl ui content_size`.
- Fase 2: add media implementado con `POST /session/:id/add-media` y MCP `cuyscout_add_media`; usa `simctl addmedia` para fotos/videos.
- Fase 2: spawn de procesos implementado con `POST /session/:id/spawn` y MCP `cuyscout_spawn`; usa `simctl spawn` con args.
- Fase 2: iCloud sync implementado con `POST /session/:id/icloud-sync` y MCP `cuyscout_icloud_sync`; usa `simctl icloud sync`.
- Fase 1: element location W3C implementado con `GET /element/:eid/location` y MCP `cuyscout_element_location`; deriva x, y, centerX, centerY de `elementRect`.
- Fase 1: mobile methods ampliados con `mobile: pushNotification`, `mobile: setContentSize`, `mobile: addMedia`, `mobile: spawn`, `mobile: icloudSync`.
- Fase 0: 10 pruebas automatizadas añadidas para push notifications, content size, add media, spawn, iCloud sync y element location.
- Fase 2: shake implementado con `POST /session/:id/shake` y MCP `cuyscout_shake`; usa `simctl ui shake`.
- Fase 2: get appearance/get content size implementados con `GET /session/:id/appearance` y `/content-size` más MCP; trackean el último valor establecido.
- Fase 2: enumerate files implementado con `POST /session/:id/enumerate` y MCP `cuyscout_enumerate_files`; usa `simctl io enumerate`.
- Fase 1: element size W3C implementado con `GET /element/:eid/size` y MCP `cuyscout_element_size`; deriva width, height de `elementRect`.
- Fase 1: double tap implementado con `POST /element/:eid/doubletap` y MCP `cuyscout_double_tap`; Native vía puente XCTest.
- Fase 1: long press implementado con `POST /element/:eid/longpress` y MCP `cuyscout_long_press`; Native vía puente con duración configurable.
- Fase 1: pinch/zoom implementado como acción `pinch(scale,velocity)` vía puente XCTest.
- Fase 1: mobile methods ampliados con `mobile: setStatusBar`, `mobile: resetApp`, `mobile: backgroundApp`, `mobile: shake`, `mobile: getAppearance`, `mobile: getContentSize`.
- Fase 0: 8 pruebas automatizadas añadidas para shake, doubleTap, longPress, pinch, enumerate, getAppearance y getContentSize.
- Fase 2: lifecycle de simulador implementado con `POST /devices/boot`, `/shutdown`, `/erase`, `/clone`, `/create`, `/rename`, `DELETE /devices/:id` y MCP; usa `simctl boot/shutdown/erase/clone/delete/create/rename`.
- Fase 2: photo library sync implementado con `POST /session/:id/pbsync` y MCP `cuyscout_pbsync`; usa `simctl pbsync`.
- Fase 2: device info enriquecido con `bundleIdentifier`, `automationName`, `manufacturer`, `deviceName`, `platformVersion`.
- Fase 2: deviceTime mejorado para intentar `simctl spawn date` antes de fallback a `Date()`.
- Fase 1: pinch/zoom disponible por REST con `POST /element/:eid/pinch` y MCP `cuyscout_pinch`; scale y velocity configurables.
- Fase 1: mobile methods ampliados con `mobile: pinch`, `mobile: bootDevice`, `mobile: shutdownDevice`, `mobile: eraseDevice`, `mobile: setBiometry`, `mobile: setLocation`, `mobile: startVideoRecording`, `mobile: stopVideoRecording`, `mobile: visualDiff`, `mobile: grantPermission`, `mobile: enumerateFiles`, `mobile: pbsync`.
- Fase 0: 3 pruebas automatizadas añadidas para deviceInfo enriquecido, deviceTime y lifecycle.
- Fase 2: transferencia de archivos implementada con `POST /session/:id/download` y `/upload` más MCP; usa `simctl io download/upload`.
- Fase 2: app container implementado con `GET /session/:id/app-container` y MCP `cuyscout_get_app_container`; usa `simctl get_app_container`.
- Fase 2: configuración del simulador implementada con `GET/POST /session/:id/config` y MCP `cuyscout_get_config`/`cuyscout_set_config`; usa `simctl config get/set`.
- Fase 1: mobile methods ampliados con `mobile: downloadFile`, `mobile: uploadFile`, `mobile: getAppContainer`, `mobile: getConfig`, `mobile: setConfig`.
- Fase 0: 6 pruebas automatizadas añadidas para file transfer, app container y simulator config.
- Fase 4: verificación de pruebas implementada con `POST /session/:id/verify-test` y MCP `cuyscout_verify_test_plan`; compila el export, ejecuta replay desde estado limpio y reporta `TestVerificationResult`.
- Fase 5: clasificación de fallos implementada con `FailureCategory` enum (product/selector/synchronization/environment/data/infrastructure) y método `classifyFailure` público.
- Fase 6: overlay de accesibilidad implementado con `GET /session/:id/accessibility-overlay` y MCP; screenshot + elementos accesibles para inspector visual.
- Fase 6: comparación visual por región implementada con `POST /session/:id/visual-compare-region` y MCP; recorta y compara región específica con tolerancia.
- Fase 6: reporte HTML mejorado con screenshot embebido y tabla de elementos de accesibilidad.
- Fase 7: política de seguridad de plugins implementada con `PluginSecurityPolicy` (requireSignature, allowedCapabilities, deniedActions); `POST /plugins/security-policy` y MCP.
- Fase 9: TLS handshake real implementado con `Network.framework` y `NWProtocolTLS`; carga identidad del Keychain.
- Fase 0-1: capabilities exhaustivas implementadas; `app`, `noReset`, `fullReset`, `browserName`, `xcodeOrgId`, `xcodeSigningId`, `wdaLocalPort` validados en `CapabilityNegotiator`.
- Fase 0: 14 pruebas automatizadas añadidas para los 7 puntos avanzables.
- Fase 6: iniciada con SDK de drivers/plugins, política de seguridad, scheduler de leases, autenticación Bearer y gateway concurrente.
- Fase 7: iniciada con eventos compactos, polling tipo BiDi, diagnóstico, reportes HTML y métricas agent-first.
- Fases 8–10: parcialmente avanzadas. Persistencia local, seguridad, CI, métricas, SDKs base, cola de sesiones, dashboard, caché, logs de consola, reglas reactivas, fingerprints semánticos, carga dinámica de drivers, endpoints de plugins, TLS, handshake TLS real, canal WebSocket BiDi de eventos y registro de workers de device farm están implementados; siguen pendientes conformidad W3C completa, WebKit Inspector real y la ejecución distribuida contra workers físicos de device farm.
- Fase 10: canal WebSocket BiDi de eventos implementado con `GET /session/:id/events/websocket`; handshake RFC 6455 (SHA-1/base64 vía CryptoKit), push de eventos como frames de texto sin polling, ping/pong, cierre limpio y límite `maxDuration` de 1 a 3600 segundos; las suscripciones BiDi protocolarias siguen pendientes.
- Fase 8: registro de workers remotos de device farm implementado con `GET/POST /workers`, `POST /workers/:id/heartbeat` y `DELETE /workers/:id`; estado `online`/`expired` por TTL renovable (`CUYSCOUT_WORKER_TTL_SECONDS`, 10–3600 s), capacidad por worker, resumen `workersOnline`/`workersExpired` en el dashboard de flota y herramientas MCP `cuyscout_register_worker`/`cuyscout_list_workers`/`cuyscout_worker_heartbeat`; la ejecución distribuida contra workers físicos sigue pendiente.
- Fase 2: `appium:app` acepta `.ipa` además de `.app`; CuyScout extrae `Payload/*.app` con caché por contenido del instalador y deduce el bundle id del `Info.plist`, cerrando el flujo "solo con el entregable".
- Fase 3: corregido el enrutamiento de `accessibilityTreeWithOptions` al puente XCTest. Caía al driver de simulador y devolvía `unsupported`, lo que dejaba `observe`, `available-actions` y `agent-state` sin acciones sugeridas: la superficie agent-first estaba inutilizable contra un dispositivo real.
- Fase 3: el árbol de accesibilidad del runner se construye desde un único `snapshot()` recorrido en memoria en vez de consultar propiedad por propiedad sobre `XCUIElement`. Una pantalla con contenido real superaba el timeout de 30 s del puente; ahora responde de inmediato.
- Fase 3: la resolución de selectores del runner usa consultas con predicado de XCTest en lugar de enumerar todos los descendientes, por el mismo motivo de coste por propiedad.
- Fase 3: el árbol del runner respeta `visibleOnly`, `interactiveOnly` y `maxElements`, y expone el tipo del elemento con nombre semántico (`textField`, `secureTextField`, …) además del `typeCode` histórico. Sin esto el motor no distinguía campos de texto y sugería `tapElement` sobre ellos.
- Fase 2: `screenshot` se captura a archivo temporal. `simctl io screenshot -` no escribe en stdout en Xcode 26: crea un archivo llamado `-` y devuelve exit 0, así que todas las capturas llegaban vacías al agente.
- Fase 2: `typeElement` asegura el foco de teclado antes de escribir y evita un segundo toque cuando el teclado ya está arriba; las coordenadas del elemento quedan desplazadas y ese toque insertaba un carácter espurio en el campo.
- Fase 2: el runner XCTest continúa tras un comando fallido (`continueAfterFailure = true`); antes un `typeText` sin foco terminaba el test y mataba la sesión del agente.
- Fase 3: `AccessibilityOptions` decodifica payloads parciales; omitir una clave ya no invalida la acción del agente.
- Fase 0: 3 pruebas automatizadas añadidas para resolución de `.ipa`, rechazo de instaladores inválidos y decodificación parcial de opciones de accesibilidad.
- Fase 0/9: `ScoutError` declaraba `errorDescription` como `String` no opcional, así que no satisfacía `LocalizedError` y `localizedDescription` devolvía el genérico "(CuyScoutCore.ScoutError error N.)". Ese texto era el que llegaba a respuestas HTTP y MCP, eventos, pasos de batch, replay y auditoría; ningún agente podía diagnosticar un fallo. Corregido a `String?`.
- Fase 5: el puente traduce el código del runner a `no such element` en vez de un `commandFailed` genérico. Como `performWithSelectorRepair` solo reacciona a `noSuchElement`, la autocuración de selectores nunca llegaba a ejecutarse; la clasificación de fallos de batch tampoco distinguía `selector` de `product`.
- Fase 2: el gateway termina la app antes de lanzar el runner. `XCUIApplication.launch()` espera a que la app quede en reposo y una app ya abierta en una pantalla con animación continua nunca llega a ese punto: el runner moría por timeout y la sesión quedaba sin puente, respondiendo `Timeout esperando respuesta de XCTest` a todo.
- Fase 3: `LessonInference` reconoce el vocabulario español de los mensajes de CuyScout además de los códigos W3C. Antes un selector roto se aprendía como "fallo del producto" y la lección recomendaba reportar un bug inexistente.
- Fase 0: 2 pruebas automatizadas añadidas para la conformidad de `LocalizedError` y la clasificación de fallos de selector en español.
- Fase 3: `StateIdentity` produce una firma semántica con SHA-256 sobre el total en vez de un prefijo de 48 caracteres del base64 de la fuente. El árbol empieza igual en todas las pantallas, así que login y home compartían identidad y lo único que la movía era el orden no determinista de las claves JSON: `changed`, la detección de bucles, la cobertura y el grafo trabajaban sobre ruido.
- Fase 3: `observe` lee el árbol una sola vez para longitud, identidad y sugerencias. Pedía tres lecturas por observación —`pageInfo`, `stateId` y sugerencias— triplicando el trabajo en el dispositivo en el bucle que el agente más ejecuta.
- Fase 3: detección de bucle fuera del modo exploration. Si las tres últimas acciones efectivas del agente son la misma y la pantalla no cambia, `agent-state` marca `loopDetected` y sugiere `stop_repeating_ineffective_action_and_choose_another`. Las lecturas de pantalla no cuentan como intentos.
- Fase 2: `readiness` distingue el puente registrado del runner realmente atendiendo (`xctest_runner_starting`), y una acción enviada durante el arranque falla al instante con ese motivo en vez de agotar treinta segundos de timeout. Antes la sesión se declaraba lista mientras `xcodebuild` seguía arrancando.
- Fase 0: 6 pruebas automatizadas añadidas para identidad de pantalla (prefijo compartido, orden de claves, geometría fraccionaria, valores escritos) y detección de repetición ineficaz.
- Documentación agent-first: `AGENT-GUIDE.md` define el contrato observar/decidir/ejecutar para agentes que solo tienen el instalador, con el recorrido real de un objetivo en lenguaje natural.
- Conformidad documentada: `CONFORMANCE.md` registra el estado por endpoint y contexto, evitando marcar como completo lo que todavía requiere infraestructura externa.

## Principios de producto

- **Agent-first:** cada operación debe ser fácil de descubrir y utilizar desde MCP.
- **Semántico antes que visual:** preferir identificadores, roles, estados y relaciones sobre píxeles o coordenadas.
- **Compacto por defecto:** devolver cambios y resúmenes; árboles completos y screenshots solo bajo demanda.
- **Determinista:** toda exploración útil debe poder reproducirse como prueba.
- **Interoperable:** aceptar clientes WebDriver/Appium existentes.
- **Seguro:** ejecución local por defecto, secretos redactados y comandos sensibles restringidos.
- **Extensible:** drivers y plugins desacoplados del núcleo.
- **Observable:** cada comando debe producir tiempos, logs y evidencia suficiente para diagnosticar fallos.

## Arquitectura objetivo

```text
Clientes existentes                    Agentes
Appium Python / WebdriverIO / Java      Codex / otros MCP clients
                 │                      │
                 └──────────┬───────────┘
                            │
                  CuyScout Protocol Gateway
             W3C WebDriver · WebDriver BiDi · MCP
                            │
                    CuyScout Agent Core
       sesiones · exploración · cobertura · recorder · compiler
                            │
                Driver API             Plugin API
              ┌─────────────┼───────────────┐
        XCUITest Driver  Simulator Driver  Android Driver
              │                             │
     XCTest/WDA Bridge                 UiAutomator2
```

## Estrategia de prioridad

### P0 — Imprescindible

Bloquea confiabilidad, interoperabilidad o uso real.

### P1 — Diferenciación

Convierte CuyScout en una herramienta especialmente eficiente para agentes.

### P2 — Escala y ecosistema

Permite múltiples plataformas, equipos y dispositivos.

### P3 — Expansión

Funciones avanzadas que consolidan una plataforma madura.

---

## Fase 0 — Endurecer la base experimental

**Prioridad:** P0  
**Esfuerzo estimado:** 2–4 semanas

### Objetivos

- Sustituir el parser HTTP de una sola lectura por un servidor concurrente robusto.
- Añadir respuestas HTTP correctas, códigos de error y envelope W3C consistente.
- Persistir sesiones, exploraciones y grabaciones en archivos versionados.
- Separar claramente protocolo, dominio, drivers y exportadores.
- Añadir pruebas de integración para servidor, MCP y puente XCTest.
- Corregir generación de secuencias anidadas y validar sintaxis de cada exportador.
- Implementar cancelación, timeout y cierre limpio de sesiones.

### Entregables

- `CuyScoutProtocol`
- `CuyScoutCore`
- `CuyScoutDrivers`
- `CuyScoutExploration`
- `CuyScoutExporters`
- Suite de pruebas end-to-end con una app fixture.

### Criterios de salida

- 100 sesiones consecutivas sin fuga de recursos.
- Dos sesiones concurrentes sin bloquear el servidor.
- Todos los errores tienen código, mensaje y contexto estructurado.
- Reiniciar CuyScout no elimina una exploración guardada.

---

## Fase 1 — Compatibilidad W3C WebDriver

**Prioridad:** P0  
**Esfuerzo estimado:** 4–6 semanas

### Objetivos

Implementar un subconjunto completo y compatible de W3C WebDriver:

- `POST /session` con `alwaysMatch`, `firstMatch` y capabilities con prefijo `appium:`.
- Estado, creación y eliminación de sesiones.
- `findElement`, `findElements` y búsqueda relativa.
- IDs de elementos estables por snapshot.
- Click, clear, value, text, attributes, enabled, displayed y rect.
- Page source XML y JSON semántico.
- Screenshot de pantalla y de elemento.
- W3C Actions para touch, pointer, keyboard y acciones encadenadas.
- Alertas, orientación, rotación, background/foreground y lifecycle básico.
- Timeouts implícito, page load y script.
- Errores WebDriver estándar.

### Entregables

- Clientes Appium Python y WebdriverIO conectándose directamente a CuyScout.
- Suite de conformidad para los endpoints implementados.
- Modo de compatibilidad que conviva con la API agent-first.

### Criterios de salida

- Una prueba Appium Python exportada por CuyScout puede ejecutarse contra CuyScout sin traducción.
- Una prueba WebdriverIO exportada puede ejecutarse contra Appium o CuyScout cambiando solo la URL.
- Al menos 80% de los comandos usados por los flujos móviles comunes funcionan con semántica W3C.

---

## Fase 2 — Driver iOS listo para producción

**Prioridad:** P0  
**Esfuerzo estimado:** 6–10 semanas

### Objetivos

- Crear un runner XCTest instalable y firmado, equivalente conceptual a WebDriverAgent.
- Automatizar compilación, firma, instalación y arranque del runner.
- Soportar simuladores y dispositivos físicos.
- Descubrir, instalar, desinstalar, lanzar, terminar y resetear aplicaciones.
- Manejar permisos, alerts del sistema, teclado, orientación y localización.
- Soportar clipboard, deep links, biometría simulada y push fixtures cuando sea posible.
- Incorporar retries controlados y reconexión del runner.
- Añadir contextos `NATIVE_APP`, Safari y WebView para apps híbridas.
- Incorporar page source consistente y búsqueda eficiente en jerarquías grandes.

### Criterios de salida

- Setup de simulador completamente automático.
- Ejecución de 500 comandos sin perder el puente.
- Recuperación automática después de reiniciar la app bajo prueba.
- Soporte documentado para dispositivo físico con signing configurable.

---

## Fase 3 — Explorador autónomo orientado a agentes

**Prioridad:** P1  
**Esfuerzo estimado:** 6–8 semanas

### Objetivos

- Crear un modelo semántico de pantalla con:
  - identidad de pantalla;
  - elementos interactivos;
  - estados y relaciones;
  - acciones disponibles;
  - transiciones observadas.
- Mantener un grafo de navegación por aplicación y versión.
- Detectar estados repetidos usando hashes estables que ignoren reloj, IDs efímeros y contenido dinámico.
- Detectar ciclos de acciones y navegación, no solo repeticiones exactas.
- Permitir presupuestos explícitos de acciones, tiempo y tokens.
- Elegir acciones por novedad, riesgo y cobertura pendiente.
- Marcar acciones destructivas y requerir política de autorización.
- Detectar callejones sin salida y volver a un checkpoint conocido.
- Crear checkpoints y restauración de estado.

### Herramientas MCP objetivo

- `cuyscout_start_exploration`
- `cuyscout_observe`
- `cuyscout_available_actions`
- `cuyscout_explore_step`
- `cuyscout_navigation_graph`
- `cuyscout_coverage`
- `cuyscout_checkpoint`
- `cuyscout_restore_checkpoint`
- `cuyscout_finalize_exploration`

### Respuesta compacta de observación

```json
{
  "screen": "Login",
  "stateId": "sha256:...",
  "changed": ["error_message"],
  "actions": [
    {"id": "login.submit", "risk": "low", "novelty": 0.82}
  ],
  "coverage": {"screens": 4, "transitions": 7},
  "budget": {"actionsRemaining": 32, "tokensHint": 410}
}
```

### Criterios de salida

- El explorador no repite un ciclo conocido más de una vez.
- Reduce al menos 70% el JSON enviado frente al árbol completo.
- Puede descubrir y reproducir las rutas principales de una app fixture sin intervención humana.

---

## Fase 4 — Compilador de exploraciones a pruebas

**Prioridad:** P1  
**Esfuerzo estimado:** 4–6 semanas

### Objetivos

- Convertir el registro de exploración en una representación intermedia estable, no directamente en strings.
- Normalizar acciones, waits, precondiciones y assertions.
- Eliminar pasos redundantes y minimizar escenarios.
- Detectar secretos y reemplazarlos por variables seguras.
- Inferir assertions a partir de transiciones observadas.
- Generar fixtures, setup, teardown y reset del estado.
- Exportar:
  - XCTest/XCUITest Swift;
  - Appium Python;
  - Appium JavaScript/TypeScript;
  - Appium Java;
  - Gherkin;
  - JSON portable de CuyScout.
- Validar sintaxis y ejecutar automáticamente la prueba generada.
- Reintentar la prueba generada desde un estado limpio antes de considerarla válida.

### Criterios de salida

- 95% de las pruebas generadas compilan en la primera exportación.
- Toda prueba entregada ha sido reproducida al menos dos veces desde estado limpio.
- Los secretos nunca aparecen en grabaciones ni código exportado.

---

## Fase 5 — Pruebas autocurativas

**Prioridad:** P1  
**Esfuerzo estimado:** 6–8 semanas

### Objetivos

- Guardar fingerprints semánticos de elementos y pantallas.
- Detectar selectores rotos por cambios de UI.
- Proponer selectores alternativos con score y explicación.
- Reparar automáticamente pruebas solo cuando la confianza supere una política configurable.
- Comparar comportamiento esperado con comportamiento observado.
- Clasificar fallos:
  - producto;
  - selector;
  - sincronización;
  - ambiente;
  - datos;
  - infraestructura.
- Generar un patch revisable en lugar de sobrescribir pruebas silenciosamente.

### Criterios de salida

- Recuperar al menos 80% de cambios simples de identifier o label.
- Cero reparaciones automáticas de baja confianza aplicadas sin aprobación.
- Cada reparación incluye evidencia antes/después.

---

## Fase 6 — Inspector y diagnóstico agent-first

**Prioridad:** P1/P2  
**Esfuerzo estimado:** 4–6 semanas

### Objetivos

- Inspector visual con screenshot y overlay de accesibilidad.
- Selección de elementos y copia de selectores CuyScout/Appium/XCTest.
- Timeline de acciones, snapshots, diffs, logs y screenshots.
- Event timings por comando y por driver.
- Screenshots y video únicamente en fallos o bajo política.
- Comparación visual con tolerancia y regiones ignoradas.
- OCR opcional para contenido no accesible.
- Reporte HTML autocontenido de cada exploración.

### Ventaja sobre Appium Inspector

El inspector debe mostrar no solo elementos, sino también:

- por qué el agente eligió una acción;
- qué cobertura añadió;
- qué riesgo detectó;
- qué assertion generó;
- cuántos tokens evitó gracias al diff.

---

## Fase 7 — Drivers y plugins

**Prioridad:** P2  
**Esfuerzo estimado:** 8–12 semanas

### Driver SDK

- Contratos Swift estables para lifecycle, elementos, acciones, source y screenshots.
- Capabilities y settings declarativos.
- Health checks y comando `cuyscout doctor`.
- Drivers cargables fuera del núcleo.

### Drivers iniciales

1. iOS XCUITest.
2. iOS Simulator.
3. Android UiAutomator2.
4. macOS Accessibility.
5. Browser/WebDriver proxy.

### Plugin SDK

- Hooks before/after command.
- Nuevos endpoints HTTP y herramientas MCP.
- Transformación de source y resultados.
- Políticas de seguridad por plugin.
- Plugins firmados y allowlist.

### Plugins iniciales

- Visual diff.
- OCR.
- Network mocking.
- Test data.
- Reporter.
- Accessibility audit.
- Agent policy.

---

## Fase 8 — Escala, device farm y ejecución distribuida

**Prioridad:** P2  
**Esfuerzo estimado:** 8–12 semanas

### Objetivos

- Scheduler de dispositivos y simuladores.
- Sesiones concurrentes y aislamiento de puertos.
- Colas, prioridades y cancelación.
- Integración con Selenium Grid.
- Workers remotos CuyScout.
- Sharding de suites y ejecución paralela.
- Reintentos por infraestructura separados de fallos de producto.
- Cache de aplicaciones y artifacts.
- Dashboard de dispositivos, sesiones y salud.

### Criterios de salida

- Diez sesiones concurrentes sin contaminación cruzada.
- Distribución automática por capabilities.
- Reanudación segura cuando un worker desaparece.

---

## Fase 9 — Seguridad y operación empresarial

**Prioridad:** P2  
**Esfuerzo estimado:** 4–6 semanas

### Objetivos

- Bind local por defecto y TLS opcional.
- Autenticación por token y scopes.
- Allowlist/denylist de comandos sensibles.
- Redacción de secretos en logs, grabaciones y MCP.
- Auditoría de acciones destructivas.
- Retención configurable de artifacts.
- Configuración mediante `.cuyscout.yaml` con schema.
- Logs JSON, OpenTelemetry y métricas Prometheus.
- Perfiles `local`, `ci` y `device-farm`.

---

## Fase 10 — WebDriver BiDi y automatización reactiva

**Prioridad:** P3  
**Esfuerzo estimado:** 6–10 semanas

### Objetivos

- Canal bidireccional para eventos de app, consola, red y contexto.
- Suscripciones a cambios de accesibilidad.
- Observación push en vez de polling del agente.
- Streaming de progreso MCP.
- Reglas reactivas: esperar evento, capturar evidencia o ejecutar assertion.
- Integración con logs y tráfico de red para explicar fallos.

---

## Capacidades con las que CuyScout debe superar a Appium

### 1. Protocolo semántico para agentes

Appium devuelve elementos y comandos. CuyScout debe devolver intención, riesgo, novedad, cobertura y costo estimado.

### 2. Compresión consciente de tokens

- Snapshots diferenciales.
- IDs estables de estado.
- Vistas compactas por tarea.
- Paginación y límites explícitos.
- Respuestas orientadas a decisión.
- Screenshots solo cuando aporten información nueva.

### 3. Exploración con cobertura y anti-bucle

- Grafo de navegación.
- Detección de ciclos semánticos.
- Presupuesto de exploración.
- Priorización por novedad y riesgo.
- Checkpoints y recuperación.

### 4. Generación verificada de pruebas

No basta con producir código: CuyScout debe compilarlo, ejecutarlo desde cero, minimizarlo y adjuntar evidencia de reproducibilidad.

### 5. Autocuración explicable

Toda reparación debe tener score, evidencia y patch revisable.

### 6. Contratos de pantalla

CuyScout podrá producir contratos versionados:

```yaml
screen: Login
requiredElements:
  - id: emailField
    role: textField
  - id: loginButton
    role: button
transitions:
  - action: loginButton.tap
    destination: Dashboard
```

Estos contratos permitirán detectar cambios de UI antes de ejecutar suites completas.

### 7. Auditoría automática de accesibilidad

Durante la exploración, CuyScout debe detectar elementos sin identifier, labels ambiguos, controles demasiado pequeños, navegación inconsistente y problemas básicos de accesibilidad.

## Matriz de paridad con Appium

| Capacidad | Actual | Objetivo | Fase |
|---|---:|---:|---:|
| Sesiones básicas | Completo | Completo | 0–1 |
| W3C WebDriver | Completo | Completo | 1 |
| XCUITest automatizado | Avanzado | Producción | 2 |
| Dispositivos físicos iOS | Avanzado | Completo | 2 |
| Native/WebView/Safari contexts | No | Completo | 2 |
| Exploración autónoma | Avanzado | Avanzado | 3 |
| Generación de pruebas | Verificada | Verificada | 4 |
| Self-healing | Avanzado | Avanzado | 5 |
| Inspector | Avanzado | Agent-first | 6 |
| Drivers externos | Avanzado | SDK estable | 7 |
| Plugins | Avanzado | SDK estable | 7 |
| Android | No | UiAutomator2 | 7 |
| Device farm | Avanzado | Distribuido | 8 |
| Seguridad empresarial | Completo | Completo | 9 |
| WebDriver BiDi | Avanzado | Reactivo | 10 |

## Métricas norte

### Eficiencia para agentes

- Tokens promedio por transición descubierta.
- Porcentaje de observaciones respondidas con diff.
- Número de acciones repetidas evitadas.
- Tiempo hasta descubrir una ruta nueva.

### Calidad de pruebas

- Porcentaje de pruebas generadas que compilan.
- Porcentaje que pasa dos veces desde estado limpio.
- Flakiness por cada 100 ejecuciones.
- Porcentaje de selectores semánticos frente a coordenadas.

### Cobertura

- Pantallas descubiertas.
- Transiciones cubiertas.
- Estados y errores cubiertos.
- Riesgos de accesibilidad detectados.

### Plataforma

- Sesiones concurrentes.
- Latencia p50/p95 por comando.
- Recuperaciones automáticas del driver.
- Fugas de procesos y recursos por sesión.

## Definition of Done para cada feature

Una funcionalidad no está terminada hasta que:

1. Tiene contrato HTTP y/o MCP documentado.
2. Tiene errores estructurados y timeouts.
3. Incluye pruebas unitarias y de integración.
4. Está cubierta por una prueba end-to-end con app fixture.
5. No expone secretos en logs o artifacts.
6. Define impacto esperado sobre tokens y latencia.
7. Mantiene compatibilidad hacia atrás o incluye migración.

## Orden recomendado de ejecución

```text
Base robusta
  → WebDriver W3C
  → Driver iOS estable
  → Exploración semántica
  → Compilador de pruebas
  → Self-healing
  → Inspector agent-first
  → Drivers/plugins
  → Device farm
  → Seguridad empresarial
  → BiDi reactivo
```

## Referencias de comparación

- [Appium documentation](https://appium.io/docs/en/latest/)
- [Appium drivers](https://appium.io/docs/en/latest/ecosystem/drivers/)
- [Appium clients](https://appium.io/docs/en/latest/ecosystem/clients/)
- [Appium plugins](https://appium.io/docs/en/latest/ecosystem/plugins/)
- [WebDriver protocol endpoints](https://appium.io/docs/en/latest/reference/api/webdriver/)
- [Session capabilities](https://appium.io/docs/en/latest/guides/caps/)
- [Session settings](https://appium.io/docs/en/latest/guides/settings/)
- [Execute methods](https://appium.io/docs/en/latest/guides/execute-methods/)
- [Selenium Grid integration](https://appium.io/docs/en/latest/guides/grid/)
- [Appium server security](https://appium.io/docs/en/latest/guides/security/)
