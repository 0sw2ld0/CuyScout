# CuyScout — Guía para agentes: automatizar una app solo con su instalador

Esta guía define el contrato entre un agente y CuyScout cuando el agente **no tiene el
código fuente de la app**, solo su entregable (`.app` de simulador, `.app` firmada
para iPhone o `.ipa`) y un objetivo
escrito en lenguaje natural.

Ejemplo de objetivo, tal como lo escribe una persona:

> Con el usuario `demo@cuywallet.com` y contraseña `Cuywallet2024`, realiza una
> transferencia entre cuentas propias de 100 soles.

El agente no necesita saber que existe un botón `btn_quick_transfer`. Lo descubre.

## Contrato

CuyScout es el único que toca el dispositivo. El agente solo hace tres cosas:

1. **Observar** — pedir el estado de pantalla y las acciones disponibles.
2. **Decidir** — elegir la siguiente acción según el objetivo.
3. **Ejecutar** — enviar esa acción y volver a observar.

Nunca conviene adivinar coordenadas ni deducir la estructura de la app: cada observación
ya entrega selectores semánticos estables.

## 1. Crear la sesión con el instalador

Si el usuario pulsó **Grabar prueba** en `CuyScout.app`, primero usa
`cuyscout_list_sessions` y continúa con esa sesión; no crees otra. El binario
`cuyscout-mcp` incluido en la app lee el perfil privado del gateway al arrancar.
Prefiere `cuyscout_observe` y `cuyscout_execute`. Si el cliente no puede usar MCP,
el `AGENTS.md` generado en el proyecto muestra las llamadas HTTP/curl equivalentes
y `scripts/cuyscout-connection.sh` carga la misma URL y token. Cambiar de
transporte nunca autoriza a repetir una acción cuyo resultado es incierto.

La única capability obligatoria es `appium:app` con la ruta del entregable. CuyScout
resuelve el `.ipa` a su `Payload/*.app`, lee `CFBundleIdentifier` del `Info.plist`, instala
con `simctl` o CoreDevice y lanza su runner XCTest genérico. Nada de esto requiere el
proyecto de la app. Por defecto elige simulador; para iPhone físico añade
`appium:driverId=ios-device` y `appium:udid`, y usa un instalador firmado para iPhone.

```bash
curl -X POST http://127.0.0.1:4723/session -H 'Content-Type: application/json' -d '{
  "capabilities": { "alwaysMatch": {
    "appium:app": "/ruta/a/CuyWallet.ipa",
    "appium:automationName": "XCUITest"
  }}}'
```

La respuesta devuelve `sessionId` y el `appium:bundleId` que CuyScout dedujo. Conviene fijar
un timeout implícito para que las búsquedas esperen a que la pantalla se estabilice:

```bash
curl -X POST http://127.0.0.1:4723/session/$SESSION/timeouts \
  -H 'Content-Type: application/json' -d '{"implicit":15000}'
```

El runner tarda unos segundos en arrancar. `GET /session/$SESSION/readiness` reporta el
bloqueo `xctest_runner_starting` mientras tanto y pasa a `interactionReady: true` cuando ya
atiende comandos. Una acción enviada antes falla al instante con ese mismo motivo, así que
conviene esperar en `readiness` —es barato, no lee la pantalla— en vez de reintentar
acciones. No hay que reinstalar ni recrear la sesión.

### App ya instalada (sin instalador)

Si solo tienes el bundle ID de una app que ya está en el dispositivo (típico: una compilación
de desarrollo en un iPhone), crea la sesión con `"appium:bundleId"` y sin `"appium:app"`.
CuyScout comprueba que esté instalada y la usa tal cual, sin reinstalarla ni borrar sus datos.
`GET /devices/<udid>/apps` lista las apps instaladas.

## 2. Observar

```bash
curl "http://127.0.0.1:4723/session/$SESSION/observe?maxActions=15"
```

Por MCP: `cuyscout_observe`. Para una decisión más completa (métricas, bloqueos, lecciones
aprendidas y sugerencia de siguiente paso) usa `cuyscout_agent_state` o `GET /agent-state`.

En HTTP, desenvuelve `value` antes de leer la observación. El contrato es:

```json
{"value":{"stateId":"state:...","texts":["identificador: texto visible"],"actions":[{"risk":"low","reason":"Control visible","action":{"type":"tapElement","selector":{"strategy":"accessibilityIdentifier","value":"identificador"}}}]}}
```

Usa `body.value.stateId`, `body.value.texts` (cadenas) y
`body.value.actions[i].action` (acción ejecutable). `risk` y `reason` pertenecen a
la sugerencia y no al comando. `readiness` también está dentro de `value`:
exige `value.interactionReady === true`; un campo ausente no significa éxito.
En scripts, configura un ID de sesión activo y cierra con `try/finally` incluso
cuando falle una aserción. Si una conexión local falla dentro de un sandbox,
solicita la ampliación de permisos correspondiente antes de concluir que el
servidor está caído. No recrees sesiones ni reintentes pagos por ese error.

En la pantalla inicial de CuyWallet la observación devuelve exactamente esto:

| acción | selector | riesgo |
|---|---|---|
| `tapElement` | `btn_toggle_password` | low |
| `tapElement` | `btn_login` | low |
| `typeElement` | `input_email` | medium |
| `typeElement` | `input_password` | high |

Tres señales que el agente debe usar:

- **`actions` y `texts`** separan actuar de verificar: los controles accionables por un lado,
  los textos visibles de la pantalla por otro. Con los dos en la misma respuesta no hace falta
  descargar el árbol completo.
- **`typeElement` vs `tapElement`** dice si el control se escribe o se toca. Está derivado
  del tipo real del elemento (`textField`, `secureTextField`, …), no de su nombre.
- **`risk`** marca campos sensibles y controles destructivos. `high` en una contraseña o en
  un botón de borrado es una señal de que el agente debe actuar deliberadamente, no por
  inercia exploratoria.
- **`stateId` y `changed`** dicen si la pantalla cambió después de la última acción. El
  `stateId` es una firma del contenido semántico: la misma pantalla da la misma identidad
  entre lecturas, sesiones y procesos, y no se mueve por animaciones. Si `changed` es `false`
  tras un tap, la acción no tuvo efecto: reintentar lo mismo es un bucle.

Si el agente insiste igualmente, `agent-state` lo corta: tres acciones efectivas iguales sin
cambio de pantalla marcan `loopDetected` y el hint
`stop_repeating_ineffective_action_and_choose_another`.

## 3. Ejecutar

```bash
curl -X POST http://127.0.0.1:4723/session/$SESSION/actions \
  -H 'Content-Type: application/json' \
  -d '{"type":"typeElement","selector":{"strategy":"accessibilityIdentifier","value":"input_email"},"text":"demo@cuywallet.com"}'
```

`typeElement` se encarga del foco de teclado por su cuenta: toca el campo, espera el teclado
software y escribe. El agente no tiene que orquestar eso.

### Delegar la elección del control a Laya (opcional)

Si `agent-state` trae el campo `decision`, CuyScout tiene Laya activo y puede elegir el control
de cada paso sin gastar tokens. Laya está **desactivado por defecto**; se activa con
`decision.layaEnabled: true`, `CUYSCOUT_LAYA_ENABLED=true`, el interruptor «Laya» de
CuyScout.app o `POST /decision/laya {"enabled": true}` (permiso `admin`).

```bash
curl -X POST http://127.0.0.1:4723/session/$SESSION/decide \
  -H 'Content-Type: application/json' \
  -d '{"step":"Seleccionar la cuenta de origen","intent":"seleccionar","options":["cuywallet"]}'
```

| Campo | Para qué |
|---|---|
| `step` | Paso corto y atómico. |
| `intent` | `tocar`, `escribir`, `seleccionar` o `confirmar`. Verificar sigue siendo tarea del agente. |
| `options` | Formas de nombrar el valor que se debe elegir. Se busca por coincidencia, con tolerancia a errores de tipeo, y Laya nunca lo adivina. |
| `avoid` | Valores que **no** se deben elegir («distinta de la cuenta de origen»). Laya no entiende negaciones, así que se filtran antes. |
| `exclude` | Selectores ya usados en pasos anteriores. |
| `irreversible` | Exige más confianza (0.6). `confirmar` ya lo implica. |
| `context` | Lo elegido antes, p. ej. «origen: Wallet Digital CUY». |

La cascada es: coincidencia determinista, opción única, Laya y, por último, el agente. Con
`decision: "chosen"`, ejecuta `candidate.action` (en un campo, reemplaza `<text>` por el valor).
Con `needs_llm`, elige tú entre `candidates`, que ya vienen acotados. `interruption: true`
significa que había un aviso del sistema (p. ej. «¿Guardar contraseña?»): se descarta y se
vuelve a pedir el mismo paso.

## 4. Verificar antes de una acción irreversible

Antes de confirmar un pago, aceptar una transferencia o borrar algo, contrasta lo que la app
afirma con el objetivo. La misma observación ya trae los textos de la pantalla en `texts`, con
su identificador:

```
label_service_result_title:      Pago exitoso
label_service_result_operation:  N° Operación: SP860351
label_service_result_amount:     Monto pagado: S/ 120.00
label_service_result_account:    Desde: Cuenta Corriente ****1234
```

`actions` es para actuar; `texts` es para verificar. Con eso el agente comprueba importe,
cuenta y concepto, y recién entonces toca `btn_service_pay`. Si algo no coincide, cancela y
reporta — no confirma "a ver qué pasa".

**Cada valor que el objetivo nombra se elige de forma explícita.** Cuenta de origen, destino,
servicio, monto: si el objetivo lo menciona, el agente lo selecciona o lo escribe y comprueba
que el resumen lo muestra. Un valor que la app trae preseleccionado **no cuenta como elegido**:
si coincide con lo pedido, se deja constancia en la verificación; si no, se cambia. Si lo pedido
no coincide exactamente con ninguna opción (un typo, un apodo), se elige la más parecida y se
dice en el reporte; si la ambigüedad es real, se detiene y pregunta. Nunca se declara éxito si
algún valor pedido no aparece en el resumen o en el comprobante.

**No descargues el árbol de accesibilidad completo para esto.** `accessibilityTreeWithOptions`
cuesta entre 7 y 12 veces lo que `observe` y es casi todo geometría y contenedores anónimos
que no se pueden accionar. Resérvalo para cuando `observe` no haya traído un dato concreto y
puedas decir cuál.

## 5. El bucle completo, para el objetivo del ejemplo

Ninguno de estos selectores estaba escrito de antemano: cada uno salió de la observación
anterior.

| # | Observación | Decisión |
|---|---|---|
| 1 | `input_email`, `input_password`, `btn_login` | Es un login. Escribir credenciales y entrar. |
| 2 | `btn_quick_transfer`, `btn_quick_pay`, `btn_quick_topup`, … | El objetivo es transferir: `btn_quick_transfer`. |
| 3 | `picker_source_account`, `picker_destination_account`, `input_amount`, `btn_transfer_continue` | Origen y destino ya son cuentas propias. Escribir `100` y continuar. |
| 4 | `btn_confirm_transfer`, `btn_cancel_transfer` + textos de confirmación | Verificar monto y cuentas, luego confirmar. |
| 5 | `label_result_title: Transferencia exitosa`, `OP673219`, `S/ 100.00` | Objetivo cumplido. Reportar el número de operación. |

## 6. Convertir la exploración en una prueba

Todo lo anterior queda grabado desde que se crea la sesión, sin pedirlo. Para dejar una
prueba reproducible basta validar y exportar:

```bash
curl "http://127.0.0.1:4723/session/$SESSION/recording/plan/validate" # detecta pasos frágiles
curl "http://127.0.0.1:4723/session/$SESSION/recording/plan/optimized"
curl "http://127.0.0.1:4723/session/$SESSION/recording/appium/typescript"
```

`validate` avisa de coordenadas, selectores frágiles, placeholders `<text>` y datos
sensibles antes de exportar. El prompt MCP `cuyscout_explore_to_test` encapsula este flujo
completo: exploración, aprendizaje, validación, replay y exportación.

## 7. Memoria entre sesiones

CuyScout recuerda entre ejecuciones. Las lecciones se guardan en
`Application Support/CuyScout/lessons.json` (o `CUYSCOUT_LESSONS_FILE`) con tres alcances:

| scope | clave | vive |
|---|---|---|
| `session` | `sessionId` | solo esa sesión |
| `project` | bundle id de la app | todas las sesiones futuras sobre esa app |
| `global` | — | todas las apps |

Una sesión nueva sobre el mismo instalador arranca ya sabiendo lo que aprendieron las
anteriores: `GET /session/$SESSION/lessons` devuelve las de scope `global` más las de
`project` cuyo bundle id coincide. Sobrevive al reinicio del gateway.

El agente aprende de dos formas:

```bash
# explícita: el agente escribe lo que descubrió
curl -X POST http://127.0.0.1:4723/lessons -H 'Content-Type: application/json' -d '{
  "scope":"project", "sessionId":"'$SESSION'",
  "title":"El boton de continuar queda bajo el teclado",
  "observation":"Tras escribir en el formulario el control siguiente no es alcanzable.",
  "recommendation":"Cerrar el teclado antes de pulsar el siguiente control.",
  "tags":["keyboard","form"]}'

# automática: infiere patrones de la grabación (fallos repetidos, ciclos, latencias)
curl -X POST http://127.0.0.1:4723/session/$SESSION/lessons/learn   -H 'Content-Type: application/json' -d '{"scope":"project","persist":false}'
```

`persist: false` devuelve los candidatos sin guardarlos, para revisarlos antes. Repetir un
aprendizaje no duplica: consolida la lección, sube `occurrences` y refuerza `confidence`.

### Aprender de un intento fallido

Una lección nacida de un solo fallo es una **hipótesis**, no un hecho. El ciclo es:

1. Si un intento no cumple el objetivo (y no fue por infraestructura: runner colgado, timeout),
   registra una lección candidata con `"confidence": 0.5` y scope `project`.
2. El siguiente intento la recibe en `GET /session/$SESSION/lessons` y en `agent-state`.
3. Al terminar ese intento, informa si la lección sirvió:

```bash
curl -X POST http://127.0.0.1:4723/lessons/$LESSON_ID/feedback \
  -H 'Content-Type: application/json' -d '{"outcome":"helped"}'   # o "failed"
```

`helped` sube la confianza (+0.15); `failed` la baja (−0.25) y cuenta el fallo en `failures`.
Por debajo de 0.3 la lección queda **descartada**: ya no se entrega a ningún agente y volver a
proponerla no la revive. Sigue visible para auditoría en `GET /lessons?includeDiscarded=true`.

No culpes a un camino de la app sin evidencia: si el agente se atascó decidiendo cuándo un paso
estaba cumplido, la lección es sobre esa decisión, no sobre la app.

`agent-state` entrega las más relevantes al contexto del momento —escritura, selectores,
latencia o bucles recientes— junto a un `nextActionHint`. No hay que consultarlas aparte.

Nunca deben guardarse credenciales ni datos personales como lecciones; CuyScout redacta
emails, tokens y números largos antes de persistir, pero la evidencia debe ser estructural.

## 8. Cuando algo falla

- `readiness.blockers` explica por qué la sesión no puede interactuar todavía.
- Un fallo de comando queda en `GET /session/$SESSION/events` con su categoría
  (`selector`, `infrastructure`, `environment`, `product`). Solo los de `infrastructure`
  merecen reintento automático.
- `POST /session/$SESSION/actions?repair=true` reintenta con un selector alternativo cuando
  el original dejó de existir, en vez de fallar de plano.
- Un comando del agente que falla no mata la sesión: el runner sigue atendiendo.
- «Failed to find matching arch» o `rosetta_runtime_missing`: la app solo trae código Intel.
  Crea la sesión con el instalador (`appium:app`) **sin fijar el dispositivo**: CuyScout usa
  «CuyScout Rosetta». Si falta el runtime universal, pide al usuario que lo prepare; no descargues
  ~10 GB por tu cuenta.

## Requisitos del entorno

- Un simulador iOS booted, o un iPhone emparejado, desbloqueado y con Modo de desarrollador.
- Xcode; CuyScout compila el runner automáticamente cuando falta.
- El gateway corriendo: `swift run cuyscout 4723`.

Para iPhone físico configura también `CUYSCOUT_DEVICE_GATEWAY_URL` con la IP de esta Mac y `CUYSCOUT_TOKEN`; expón el
gateway con `CUYSCOUT_BIND_ADDRESS` en la misma IP. Mantén el dispositivo
desbloqueado y acepta el primer aviso de red local de ScoutRunner. El flujo completo
de comandos está en el README, sección “Crear pruebas en un iPhone físico”.
El equipo que firma el runner se detecta en la Mac (cuentas de Xcode y certificados);
`CUYSCOUT_DEVELOPMENT_TEAM` solo hace falta si hay varios y ninguno está elegido en Xcode.
Si `/doctor` marca `signing_team` como no disponible, pide al usuario iniciar sesión en
Xcode → Ajustes → Cuentas.

Para el ejemplo de esta guía, el instalador se genera con
`bash Scripts/build_cuywallet_installer.sh`, que produce `CuyWallet.app` y `CuyWallet.ipa`
en `.build/installers/`.
