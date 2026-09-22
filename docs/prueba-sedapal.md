# El prompt de la prueba: pago de Sedapal en Cuy Wallet

Este es el prompt exacto usado en las cuatro corridas del benchmark (Opus 5, Sonnet 5,
Haiku 4.5, y la repetición pidiendo una prueba ejecutable). Solo cambia el modelo que lo
recibe y, en la segunda medición, el entregable obligatorio al final; el escenario
Gherkin es el mismo en las dos.

Se lanzó un agente por herramienta (CuyScout / Appium) y por modelo, cada uno sin ver el
prompt ni la sesión del otro, sobre un simulador limpio.

## Agente CuyScout

```
Eres un agente de automatización iOS. Conduces una app de la que NO tienes el código
fuente: solo su instalador y un objetivo.

HERRAMIENTA: un gateway HTTP compatible WebDriver en http://127.0.0.1:4801

REGLAS ESTRICTAS:
- Interactúa con la app SOLO por HTTP contra el puerto 4801.
- PROHIBIDO leer el código fuente de la app en
  /Users/oswaldoleon/Documents/Agentes/CuyWallet.
- PROHIBIDO leer el código del gateway bajo
  /Users/oswaldoleon/Documents/cuycoders/workspace/CuyCards/CuyScout/Sources, /Runner o
  /Tests.
- PROHIBIDO leer o escribir en scratchpad, ni archivos con "meter" o .jsonl.
- PROHIBIDO pedir screenshots.
- SÍ puedes leer: /Users/oswaldoleon/Documents/cuycoders/workspace/CuyCards/CuyScout/AGENT-GUIDE.md
  y .claude/skills/cuyscout-ios/SKILL.md

ABRIR SESIÓN:
POST /session con
{"capabilities":{"alwaysMatch":{"appium:app":"<ruta al .ipa>","appium:automationName":"XCUITest","appium:udid":"<udid del simulador>"}}}
Después POST /session/ID/timeouts con {"implicit":8000}.
Espera en GET /session/ID/readiness hasta que deje de reportar xctest_runner_starting.

ESCENARIO:
  Dado que inicio sesión con demo@cuywallet.com / Cuywallet2024
  Cuando pago un recibo de Sedapal por el suministro 19891201 usando Cuy Wallet
  Entonces veo el comprobante con el número de operación y el monto pagado
  Y verifico el número de operación ANTES de confirmar cualquier acción irreversible

ENTREGABLE OBLIGATORIO:
Prueba automatizada ejecutable en:
  <ruta de salida>/cuyscout-<modelo>.ts
Selectores semánticos, no coordenadas.

AL TERMINAR:
1. Escribe el archivo de la prueba.
2. Cierra la sesión con DELETE /session/ID.
3. Reporta: N° de operación, monto, llamadas HTTP, cómo obtuviste la prueba.

Trabaja de forma eficiente: cada llamada HTTP cuesta.
```

## Agente Appium

```
Eres un agente de automatización iOS. Conduces una app de la que NO tienes el código
fuente: solo su instalador y un objetivo.

HERRAMIENTA: Appium 3.2.2 con XCUITest, servidor W3C WebDriver en http://127.0.0.1:4901

REGLAS ESTRICTAS:
- HTTP contra el puerto 4901 solamente.
- PROHIBIDO: código fuente en /Users/oswaldoleon/Documents/Agentes/CuyWallet, gateway en
  /Users/oswaldoleon/Documents/cuycoders/workspace/CuyCards/CuyScout, scratchpad,
  archivos "meter"/.jsonl, screenshots.

ABRIR SESIÓN:
POST /session con
{"capabilities":{"alwaysMatch":{"platformName":"iOS","appium:automationName":"XCUITest","appium:udid":"<udid del simulador>","appium:bundleId":"com.cuywallet.app","appium:noReset":true}}}
WebDriverAgent ya está precalentado.

ESCENARIO:
  Dado que inicio sesión con demo@cuywallet.com / Cuywallet2024
  Cuando pago un recibo de Sedapal por el suministro 19891201 usando Cuy Wallet
  Entonces veo el comprobante con el número de operación y el monto pagado
  Y verifico el número de operación ANTES de confirmar cualquier acción irreversible

ENTREGABLE OBLIGATORIO:
Prueba TypeScript/WebdriverIO/Appium en:
  <ruta de salida>/appium-<modelo>.ts
Selectores semánticos (accessibility id o predicate), no coordenadas.

AL TERMINAR:
1. Escribe el archivo de la prueba.
2. Cierra la sesión con DELETE /session/ID.
3. Reporta: N° de operación, monto, llamadas HTTP, cómo obtuviste la prueba.

Trabaja de forma eficiente: cada llamada HTTP cuesta.
```

## Qué se mantuvo igual y qué cambió entre corridas

| | Se mantiene igual | Cambia |
|---|---|---|
| Escenario Gherkin | sí, palabra por palabra | — |
| Credenciales, suministro (19891201) | sí | el monto lo elige cada agente: el escenario no lo fija |
| Prohibiciones (código fuente, screenshots, scratchpad) | sí | — |
| Modelo que decide los pasos | — | Opus 5 / Sonnet 5 / Haiku 4.5, vía `/model` antes de lanzar el agente |
| Entregable obligatorio | la prueba ejecutable siempre se pidió, en las cuatro corridas | el nombre de archivo incluye el modelo, para no pisar corridas anteriores |
| Simulador | limpio en cada corrida | UDID distinto por corrida (nuevo simulador o reinicio) |

**Por qué el prompt prohíbe explícitamente leer el código fuente y el gateway.** Es la
condición central del experimento: un agente que ve el código no necesita observar la
pantalla del mismo modo, así que ese atajo tendría que estar cerrado en las dos
herramientas por igual para que la comparación mida lo que dice medir.

**Por qué prohíbe screenshots.** No es una limitación de la app: es intencional. Un
screenshot cuesta entre 75 000 y 400 000 tokens (ver [`README.md`](../README.md)) y
hubiera dominado la medición sin decir nada sobre la diferencia entre protocolos.

**Por qué "trabaja de forma eficiente: cada llamada HTTP cuesta".** Es la única
instrucción de optimización en el prompt, y es igual para los dos agentes. No se le dijo
a ninguno cuál API usar ni cómo verificar: esa decisión, en la que aparece la ventaja de
CuyScout, salió del agente leyendo la documentación de su propia herramienta —
[`AGENT-GUIDE.md`](../AGENT-GUIDE.md) y la
[skill](../.claude/skills/cuyscout-ios/SKILL.md) en el caso de CuyScout.

## Ver también

- [`README.md`](../README.md) — los números que salieron de correr este prompt.
- [`docs/architecture.md`](architecture.md) — por qué la diferencia es estructural.
- [`Scripts/evidence/run-20260902-benchmark-appium/`](../Scripts/evidence/run-20260902-benchmark-appium/) — registros crudos de las corridas.
