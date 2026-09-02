# CuyScout — Guía para agentes: automatizar una app solo con su instalador

Esta guía define el contrato entre un agente y CuyScout cuando el agente **no tiene el
código fuente de la app**, solo su entregable (`.app` de simulador o `.ipa`) y un objetivo
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

La única capability obligatoria es `appium:app` con la ruta del entregable. CuyScout
resuelve el `.ipa` a su `Payload/*.app`, lee `CFBundleIdentifier` del `Info.plist`, instala
con `simctl` y lanza su runner XCTest genérico. Nada de esto requiere el proyecto de la app.

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

El runner tarda unos segundos en registrarse. `GET /session/$SESSION/readiness` responde
`interactionReady: true` cuando el puente está vivo; hasta entonces las observaciones pueden
llegar vacías. No hay que reinstalar ni recrear la sesión mientras tanto.

## 2. Observar

```bash
curl "http://127.0.0.1:4723/session/$SESSION/observe?maxActions=15"
```

Por MCP: `cuyscout_observe`. Para una decisión más completa (métricas, bloqueos, lecciones
aprendidas y sugerencia de siguiente paso) usa `cuyscout_agent_state` o `GET /agent-state`.

En la pantalla inicial de CuyWallet la observación devuelve exactamente esto:

| acción | selector | riesgo |
|---|---|---|
| `tapElement` | `btn_toggle_password` | low |
| `tapElement` | `btn_login` | low |
| `typeElement` | `input_email` | medium |
| `typeElement` | `input_password` | high |

Tres señales que el agente debe usar:

- **`typeElement` vs `tapElement`** dice si el control se escribe o se toca. Está derivado
  del tipo real del elemento (`textField`, `secureTextField`, …), no de su nombre.
- **`risk`** marca campos sensibles y controles destructivos. `high` en una contraseña o en
  un botón de borrado es una señal de que el agente debe actuar deliberadamente, no por
  inercia exploratoria.
- **`stateId` y `changed`** dicen si la pantalla cambió después de la última acción. Si
  `changed` es `false` tras un tap, la acción no tuvo efecto: reintentar lo mismo es un bucle.

## 3. Ejecutar

```bash
curl -X POST http://127.0.0.1:4723/session/$SESSION/actions \
  -H 'Content-Type: application/json' \
  -d '{"type":"typeElement","selector":{"strategy":"accessibilityIdentifier","value":"input_email"},"text":"demo@cuywallet.com"}'
```

`typeElement` se encarga del foco de teclado por su cuenta: toca el campo, espera el teclado
software y escribe. El agente no tiene que orquestar eso.

## 4. Leer la pantalla para verificar

Antes de una acción irreversible —confirmar un pago, aceptar una transferencia— el agente
debe leer lo que la app afirma y contrastarlo con el objetivo. El árbol de accesibilidad con
`interactiveOnly: false` entrega los textos:

```bash
curl -X POST http://127.0.0.1:4723/session/$SESSION/actions \
  -H 'Content-Type: application/json' \
  -d '{"type":"accessibilityTreeWithOptions","options":{"interactiveOnly":false,"maxElements":120}}'
```

En la pantalla de confirmación de CuyWallet eso devuelve:

```
label_confirm_title    ¿Confirmar transferencia?
label_confirm_from     Desde: Cuenta Corriente ****1234
label_confirm_to       Hacia: Wallet Digital CUY
label_confirm_amount   Monto: S/ 100
```

Con eso el agente comprueba que son cuentas propias y que el monto es el pedido, y recién
entonces toca `btn_confirm_transfer`. Si algo no coincide, cancela y reporta — no confirma
"a ver qué pasa".

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

Todo lo anterior queda grabado. Para dejar una prueba reproducible:

```bash
curl -X POST http://127.0.0.1:4723/session/$SESSION/recording/start   # antes de explorar
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

## Requisitos del entorno

- Un simulador iOS booted.
- El runner genérico compilado una sola vez: `bash Scripts/build_scout_runner.sh`.
- El gateway corriendo: `swift run cuyscout 4723`.

Para el ejemplo de esta guía, el instalador se genera con
`bash Scripts/build_cuywallet_installer.sh`, que produce `CuyWallet.app` y `CuyWallet.ipa`
en `.build/installers/`.
