# CuyScout

CuyScout es una base Swift para automatización de dispositivos con una API HTTP local inspirada en WebDriver/Appium. Sí, Swift es una buena opción para el núcleo en macOS: permite integrar `simctl`, XCTest/XCUITest y APIs nativas con poca fricción.

## Cuánto cuesta, medido

### Primera prueba: ejecutar el escenario

El mismo escenario Gherkin —iniciar sesión, pagar un recibo de Sedapal, verificar el código
de operación— ejecutado por seis agentes sin acceso al código de la app: tres con CuyScout y
tres con Appium 3.2.2, uno por modelo, sobre simuladores iguales.

| Modelo | CuyScout | Appium 3.2.2 | Ventaja |
|---|---:|---:|---:|
| Opus 5 | **3 946** | 65 476 | 16,6x |
| Sonnet 5 | **3 689** | 72 199 | 19,6x |
| Haiku 4.5 | **12 551** | 128 648 | 10,2x |

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

### Segunda prueba: terminar con una prueba ejecutable

La primera medición respondía "¿cuánto cuesta ejecutar el escenario?". Pero una corrida que
no deja nada reutilizable desperdicia el trabajo, así que la segunda mide otra cosa: **cuánto
cuesta terminar con una prueba automatizada ejecutable en la mano.** Mismo escenario, mismos
simuladores, mismo montaje, y para los dos agentes el mismo entregable obligatorio: un `.ts`
que corra el flujo con selectores semánticos.

| Opus 5 decidiendo los pasos | CuyScout | Appium 3.2.2 | Ventaja |
|---|---:|---:|---:|
| Llamadas HTTP | 25 | 30 | — |
| **Tokens totales** | **5 354** | 92 478 | 17,3x |
| Lecturas de pantalla | 8 | 8 | — |
| Coste por lectura | 380 | 11 298 | 29,8x |
| Coste de dejar la prueba | 941 (2 llamadas) | escrita a mano | — |
| Prueba resultante | 126 líneas, 13 aserciones | 163 líneas, 9 aserciones | — |

Los dos completaron el pago —operaciones SP427700 y SP380094— y las dos pruebas usan solo
selectores semánticos: **cero coordenadas** en ambas.

La diferencia está en de dónde sale la prueba. En CuyScout la sesión ya venía grabada, así
que `recording/appium/typescript` devolvió el helper, las capabilities y la secuencia de
pasos con sus selectores por 941 tokens; el agente solo repuso los valores que CuyScout
redacta por seguridad y añadió las aserciones, que una grabación no puede inventar porque
registra lo que se hizo, no lo que debía cumplirse. En Appium no hay nada de eso: el agente
escribió el archivo entero a mano.

**El aviso más importante de esta medición.** Los 92 478 tokens son lo que viaja por el
cable, y el coste de que Appium escriba la prueba a mano no está ahí: son tokens de salida
del modelo, que este proxy no mide. Medido en contexto total consumido, los dos agentes
acabaron parecidos —64 620 y 60 010 tokens—, porque el de Appium filtró el XML por shell
antes de leerlo. La ventaja en el cable es estructural y se sostiene; la ventaja en contexto
depende de que el agente sepa y pueda filtrar, y un cliente que hable solo por MCP no puede.
Los dos agentes eligieron importes distintos (S/ 120,00 y S/ 85,50) porque el escenario no
lo fijaba: no afecta al coste, pero conviene saberlo.

**¿También aquí depende del modelo?** Se repitió exactamente este mismo montaje y el mismo
entregable obligatorio con Sonnet 5 decidiendo los pasos, en vez de Opus 5.

| Modelo | CuyScout | Appium 3.2.2 | Ventaja |
|---|---:|---:|---:|
| Opus 5 | 5 354 | 92 478 | 17,3x |
| Sonnet 5 | 4 999 | 99 798 | 20,0x |

CuyScout varía un 7 % entre modelos (5 354 → 4 999); Appium, un 8 % (92 478 → 99 798). La
ventaja de dejar la prueba grabada en vez de escrita a mano no depende de qué modelo decide:
con Sonnet, `recording/appium/typescript` volvió a devolver casi toda la prueba —910 tokens
en dos llamadas— y el agente completó lo mismo que con Opus: valores redactados y
aserciones. Sonnet también pagó S/ 120,00 con CuyScout y S/ 85,50 con Appium, la misma
partición de la corrida anterior, así que no fue casualidad del prompt sino de cada
herramienta: ninguna fija el monto en el escenario, cada agente decide el suyo.

Un aviso honesto de esta repetición: `recording/plan/validate` marcó el plan de CuyScout
como `valid:false` por un timeout transitorio de XCTest en la primera lectura de pantalla,
no por el escenario. El agente lo reportó y siguió; la prueba exportada quedó completa y
correcta, pero el plan subyacente conserva el aviso del paso fallido.

Evidencia, pruebas generadas y registros crudos en
[`Scripts/evidence/run-20260921-benchmark-prueba-generada/`](Scripts/evidence/run-20260921-benchmark-prueba-generada/).

### Luna y Terra: evaluación controlada del 22 de septiembre

Última repetición autónoma, solo CuyScout: Luna falló en el manejo de una sesión ya
creada; Terra verificó el resumen con tres assertions y fue bloqueado por el entorno
al confirmar. Se encontró y corrigió un falso negativo del validador TypeScript
(219 tests pasan). Ninguno completó el escenario/replay en esta repetición.
[Resultados y originales](Scripts/evidence/run-20260922-cuyscout-models-rerun/RESULTADOS.md).

Actualización posterior de CuyScout: el exportador autónomo corregido completó una
reproducción íntegra en una instalación DEMO limpia, con resumen previo y comprobante
verificados. [Correcciones, archivo exacto y evidencia](Scripts/evidence/run-20260922-cuyscout-replay-fixed-export2/RESULTADOS.md).
Es una validación de producto, no una repetición de las mediciones de modelos de abajo.

Cuatro corridas nuevas por HTTP, sin código de la app ni `AGENT-GUIDE.md`. CuyScout se
descubre mediante `/agent-help`. Límites externos: 80 llamadas, 8 minutos y cortes por
repetición. Los fallos confirmados de CuyScout se detuvieron, repararon y repitieron en
una tarea limpia; los fallos del modelo y bloqueos del entorno no se ocultaron.

| Modelo / herramienta | Llamadas HTTP | Tokens de tráfico | Escenario | Prueba original |
|---|---:|---:|---|---|
| Luna / CuyScout | 25 | 6 740 | Resumen y comprobante verificados; SP501127 | Replay falla esperando resumen visible |
| Luna / Appium | 24 | 51 094 | Resumen verificado; pago bloqueado por el entorno | Parcial; error de capabilities |
| Terra / CuyScout | 20 | 4 599 | Pago SP602301; omitió observar el resumen previo | Replay cortado por límite de llamadas |
| Terra / Appium | 34 | 114 549 | Pago S/ 27.50, operación SP201817 | Replay falla: `$` no definido |

**Tres corridas pagaron, una omitió verificar el resumen; ningún original completó su reproducción.**
No se calculan ventajas de tokens con flujos incompletos. Las cifras son tráfico HTTP con
`cl100k_base`, no consumo total ni coste del modelo. Sonnet queda como referencia histórica
(4 999 / 99 798 tokens en la segunda prueba), con diferencias de ayuda, versión y límites.

Se corrigieron dos defectos reales: ayuda HTTP que mostraba argumentos MCP y producía
errores 500 (`043f12d`), y un tipo incompatible en el helper TypeScript exportado (`51c3bb6`).
Se repitió CuyScout desde cero tras las correcciones. Pasaron 211 tests Swift, 6 del controlador,
los contratos HTTP/MCP y el helper TypeScript corregido. Todos los intentos anteriores,
incluidos fallos del agente y errores de preparación del coordinador, se conservan separados.

[Resultados detallados, metodología, originales y registros](Scripts/evidence/run-20260922-luna-terra/RESULTADOS.md).
La reproducción se midió aparte y los rechazos de seguridad no se sortearon.

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

## Apps que solo traen código Intel (Rosetta)

Algunos instaladores de simulador solo incluyen `x86_64` (Intel). En Apple Silicon el simulador normal (`arm64`) se niega a instalarlos («Failed to find matching arch»). CuyScout lo detecta solo al recibir el `.app`/`.ipa` y usa el simulador **«CuyScout Rosetta»**, arrancado con `--arch=x86_64`; el runner XCTest se compila también en `x86_64`, en una carpeta aparte. Las apps universales o `arm64` no cambian nada.

Requiere Rosetta (`softwareupdate --install-rosetta --agree-to-license`) y un runtime de iOS en variante **universal**. Apple no publica esa variante para todas las versiones (iOS 26.5 no la tiene; 26.4 sí, ~10 GB). Se prepara una sola vez:

- CuyScout.app: **Almacenamiento › Simulador Rosetta › Preparar**.
- API: `POST /devices/rosetta/prepare {"download": true}` (permiso `admin`) y `GET /devices/rosetta` para seguir el avance. Sin `download: true` nunca se descarga nada.

`/doctor` muestra el chequeo opcional `rosetta_simulator`.

## Ejecutar

```bash
cd CuyScout
swift run cuyscout
```

Por defecto escucha en `127.0.0.1:4723`. Cambia el puerto con `swift run cuyscout 4724`.

## App de macOS

CuyScout también tiene una interfaz SwiftUI. Se empaqueta junto al mismo gateway que usa la terminal:

```bash
Scripts/build_cuyscout_app.sh
open .build/CuyScout.app
```

**Mientras desarrollas CuyScout**, enlaza la compilación del repo en Aplicaciones una sola vez. Así la abres desde Spotlight, Launchpad o el Dock, siempre se abre la última compilación y funciona la ruta `/Applications/CuyScout.app/Contents/MacOS/cuyscout-mcp` que usan los proyectos generados:

```bash
ln -s "$PWD/.build/CuyScout.app" /Applications/CuyScout.app
```

Después de cada cambio, recompila y reabre (una ventana ya abierta conserva la versión anterior; ciérrala con ⌘Q):

```bash
Scripts/build_cuyscout_app.sh && open .build/CuyScout.app
```

No copies la app a Aplicaciones en tu Mac de desarrollo: la copia se queda en la versión en que la copiaste. Copiarla es para instalarla en otra Mac, a partir del ZIP (ver abajo).

Requiere una Mac Apple Silicon con macOS 13 o posterior, Xcode y las herramientas de línea de comandos. El script compila en modo release, copia `cuyscout` y `cuyscout-app`, genera el icono `.icns` y aplica una firma ad hoc. La app resultante está en `.build/CuyScout.app`. Para crear un ZIP que conserve la estructura y los metadatos del paquete:

```bash
ditto -c -k --sequesterRsrc --keepParent .build/CuyScout.app .build/CuyScout-macos-arm64.zip
shasum -a 256 .build/CuyScout-macos-arm64.zip
```

Las versiones etiquetadas `v*` generan ese ZIP en [GitHub Releases](https://github.com/0sw2ld0/CuyScout/releases). Una vez confirmados y subidos los cambios, crea una versión con `git tag v0.1.0 && git push origin v0.1.0` (o usa la siguiente versión disponible). También se puede lanzar manualmente el workflow **Build macOS app** y descargar su artifact. En otra Mac, descomprime el ZIP y mueve `CuyScout.app` a Aplicaciones. Esta compilación **no está notarizada**: es una build de desarrollo, por lo que Gatekeeper puede impedir abrirla. Para una distribución pública sin advertencias se necesita firma Developer ID y notarización de Apple.

La interfaz, el gateway, `cuyscout-mcp` y **el código fuente del runner XCTest** vienen en el `.app`. En la Mac de destino se requiere Xcode y un simulador iOS o un iPhone físico preparado para desarrollo; CuyScout compila automáticamente el runner la primera vez y guarda esa compilación fuera del paquete firmado. No necesita copiar ni instalar el repo CuyScout. Los artefactos, fixtures y proyectos de pruebas se copian por separado; no se incluyen en el ZIP. En proyectos creados con versiones anteriores, vuelve a ejecutar `cuyscout init` para actualizar los scripts generados (conserva `features/` y los fixtures existentes).

El diseño visual de referencia está en `Assets/Mockups/CuyScout-dashboard-concept.png`. El icono maestro está en `Assets/Brand/CuyScoutIcon-master.png`; el script genera los tamaños de macOS y empaqueta `Contents/Resources/CuyScout.icns`. Los colores y componentes del panel se implementan en SwiftUI, no dependen de una captura estática. Más detalles de los recursos y sus prompts en `Assets/README.md`.

En la app puedes **Abrir proyecto…** para seleccionar la carpeta raíz creada previamente con `cuyscout_init.sh` o `cuyscout init` (también acepta seleccionar su `output/` o `features/`). No se vuelven a generar archivos ni se duplica el proyecto: se registra la carpeta y se muestran las pruebas existentes de `features/` y `output/`. «Nuevo proyecto» crea uno desde la interfaz **sin exigir el repositorio**; el campo del repo es opcional si prefieres usarlo como respaldo. Una vez abierto puedes ver escenarios y validaciones, elegir instaladores separados para simulador e iPhone físico, pulsar **Grabar prueba**, observar una sesión del agente y reejecutar artefactos `.cuyscout.json`. Las rutas elegidas se guardan en `.cuyscout-project.json` para que también las use el agente. Los valores de replay se leen de `fixtures/replay-values/<escenario>.json`; los resultados recientes quedan en las preferencias locales sin guardar esos valores. El panel Artefactos muestra lo persistido en el gateway y el Resumen muestra sus dispositivos.

En el detalle de una prueba con artefacto, **Exportar para Appium…** permite elegir **TypeScript (`.ts`)** o **Python (`.py`)** y escoger dónde guardar el script (por defecto en `output/`). Usa el código ya guardado en la grabación; no vuelve a ejecutar la prueba. Revisa los placeholders de datos redactados y las acciones antes de lanzarlo con Appium. TypeScript usa WebdriverIO; Python usa Appium Python Client.

La ventana se conecta a `http://127.0.0.1:4723` por defecto. Si el gateway ya está activo, lo reutiliza; si no, **Iniciar gateway** ejecuta el binario incluido en el `.app`. En Resumen, pulsa el indicador de conexión para cambiar la URL o proporcionar un token para esa sesión. La terminal sigue funcionando con `swift run cuyscout 4723` o con el binario `.build/CuyScout.app/Contents/MacOS/cuyscout 4723`. Ambas interfaces consultan el mismo servidor y su almacén de artefactos. Al pulsar «Reejecutar prueba» se elige un dispositivo compatible y la preparación; la app muestra el preflight antes de ejecutar.

## Generar un proyecto de pruebas (`cuyscout init`)

En vez de escribir a mano los scripts de infraestructura (levantar el gateway, abrir/cerrar
una sesión por escenario), `cuyscout init` los genera:

```bash
swift run cuyscout init /ruta/al/proyecto-de-pruebas \
  --app-path /ruta/a/MiApp.app \
  --app-name MiApp \
  --cuyscout-repo /ruta/a/este/repo
```

Esa forma exige estar parado en este repo (`cd` aquí antes de `swift run`). Para correrlo
desde cualquier carpeta sin acordarte de esa ruta, usa el wrapper
`Scripts/cuyscout_init.sh`, que resuelve el repo por sí mismo:

```bash
/ruta/a/este/repo/Scripts/cuyscout_init.sh /ruta/al/proyecto-de-pruebas \
  --app-path /ruta/a/MiApp.app --app-name MiApp
```

Antes de correrlo, el proyecto destino solo necesita tener sus `.feature` en
`features/` — eso lo escribes tú o el agente, `cuyscout init` nunca lo toca. El
comando genera o actualiza:

- `scripts/{ensure-cuyscout,open-session,close-session}.sh` — se **regeneran siempre**
  (son generados, no contenido del usuario). Implementan el contrato de
  `AGENT-GUIDE.md`: una sesión de CuyScout por escenario, con `open-session.sh` como
  hook "Before" y `close-session.sh` como hook "After" (valida el plan, exporta a
  TypeScript y borra la sesión).
- `fixtures/credentials.test.json` — se crea **solo si no existe**, para no pisar
  credenciales que ya rellenaste.
- `output/` — carpeta para las pruebas exportadas.
- `AGENTS.md` — se crea si falta, o se **actualiza** si ya existe: solo reemplaza el
  bloque delimitado por `<!-- cuyscout:init:start -->` / `<!-- cuyscout:init:end -->`,
  preservando cualquier contenido que hayas agregado a mano fuera de esos marcadores.
  Ahí queda documentado el flujo para cualquier agente que abra el proyecto (Claude
  Code, Cursor, Codex CLI, etc. reconocen `AGENTS.md` de forma nativa), cubriendo
  tanto generar con CuyScout como reproducir un `.ts` ya exportado con Appium puro.

### Crear pruebas en un iPhone físico

**Flujo corto con `CuyScout.app`:** abre el proyecto, selecciona una vez
**Instalador firmado para iPhone…** y pulsa **Grabar prueba**. La primera vez
indica el Team ID de Xcode; la app detecta la IP local, genera un token privado,
inicia el gateway y escoge automáticamente un iPhone libre. El iPhone debe estar
desbloqueado para aceptar los permisos iniciales. Después, el agente obtiene la
misma sesión con `cuyscout_list_sessions` y usa `cuyscout_observe` /
`cuyscout_execute`. La vista de CuyScout.app puede mostrar esa sesión sin cerrarla
al salir del panel. El botón **prepara y graba la sesión**, pero no ejecuta un
agente por sí solo: el agente debe estar conectado a `cuyscout-mcp` o usar el
fallback HTTP indicado en el `AGENTS.md` del proyecto.

El binario MCP incluido en el paquete está en
`/Applications/CuyScout.app/Contents/MacOS/cuyscout-mcp`. Al iniciar desde esa
Mac lee automáticamente el perfil privado de conexión que creó la app; no hay que
copiar el token a la configuración del agente. Si el cliente no ofrece MCP,
`scripts/open-session.sh`, `scripts/close-session.sh` y las llamadas curl del
`AGENTS.md` usan el mismo perfil. Para actualizar un proyecto anterior ejecuta
`cuyscout init` de nuevo: conserva `features/`, `output/` y los fixtures.

Lo siguiente es el montaje **manual/avanzado** para CI o diagnósticos, no el
procedimiento normal de grabación:

El iPhone debe estar emparejado, desbloqueado y con Modo de desarrollador activo. La
app bajo prueba necesita una compilación **para iPhone** firmada por tu equipo Apple
(`.app` de `Debug-iphoneos` o `.ipa` instalable); una `.app` de simulador no sirve.
Mac e iPhone deben compartir una red local de confianza. En el primer arranque,
mantén el iPhone desbloqueado y acepta el aviso de acceso a la red local para
**ScoutRunner**; después el permiso se puede revisar en Ajustes → Privacidad y
seguridad → Red local. Si iOS solicita autorización de XCTest/automatización,
acéptala.

```bash
# Terminal 1: usa la IP LAN de esta Mac y tu Team ID de Xcode.
export CUYSCOUT_BIND_ADDRESS=192.168.1.10
export CUYSCOUT_DEVICE_GATEWAY_URL=http://192.168.1.10:4723
export CUYSCOUT_DEVELOPMENT_TEAM=TU_TEAM_ID
export CUYSCOUT_TOKEN=$(openssl rand -hex 24)
swift run cuyscout 4723
```

En otra terminal, usa **el mismo token** (compártelo mediante un almacén seguro o un
archivo local privado, nunca lo subas a Git), el UDID que devuelve `/devices` y el
instalador firmado:

```bash
export CUYSCOUT_URL=http://192.168.1.10:4723
export CUYSCOUT_TOKEN=EL_MISMO_TOKEN
curl -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "${CUYSCOUT_URL}/devices"
export CUYSCOUT_DRIVER_ID=ios-device
export CUYSCOUT_DEVICE_ID=UDID_DEL_IPHONE
export CUYSCOUT_APP_PATH=/ruta/a/Debug-iphoneos/MiApp.app
SESSION=$(scripts/open-session.sh)
# El agente usa observe/execute sobre esta sesión para grabar el escenario.
scripts/close-session.sh "$SESSION" nombre-del-escenario
```

Los comandos `scripts/*` se ejecutan dentro del proyecto de pruebas creado o
regenerado con `cuyscout init`. Para reejecutar un artefacto grabado en iPhone:

```bash
export CUYSCOUT_REPLAY_DEVICE_ID=UDID_DEL_IPHONE
export CUYSCOUT_REPLAY_APP_PATH=/ruta/a/Debug-iphoneos/MiApp.app
scripts/replay-cuyscout.sh nombre-del-escenario
```

El artefacto conserva el tipo de dispositivo: una grabación de simulador no se
convierte automáticamente en prueba física. Para crearla en iPhone, abre una sesión
con `CUYSCOUT_DRIVER_ID=ios-device` y grábala allí. El gateway expuesto por HTTP
transporta acciones y posibles datos sensibles sin cifrado: úsalo solo en una red
local de confianza o detrás de un proxy TLS privado. Si el iPhone rechaza la red
local, `/readiness` quedará en `xctest_runner_starting` hasta conceder ese permiso.

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

Para ejecutar una prueba guardada después de cerrar su sesión, usa el replay en frío del gateway:

```bash
curl --fail-with-body -X POST http://127.0.0.1:4723/artifacts/SESSION_ID/replay \
  -H 'Content-Type: application/json' \
  -d '{"resetApp":true}'
```

CuyScout restaura el artefacto, inicia el simulador si está apagado, prepara la app, arranca el runner XCTest y espera hasta 120 segundos a que se conecte antes de ejecutar los pasos. Al terminar (también ante un fallo) cierra la sesión temporal y libera el dispositivo; el artefacto original se conserva para repetir la prueba. No hace falta Node, WebdriverIO ni ejecutar el `.ts` exportado. En el repo se puede precompilar el runner con `Scripts/build_scout_runner.sh`; el `.app` descargado compila el suyo automáticamente en la primera ejecución.

Los proyectos creados con `cuyscout init` guardan junto al `.ts` un paquete completo `output/<escenario>.cuyscout.json`. Ese paquete se puede mover a otro gateway e importar sin Node:

```bash
scripts/replay-cuyscout.sh transferencia-propia
```

`close-session.sh` guarda automáticamente los valores concretos de la grabación en `fixtures/replay-values/<escenario>.json`, con permisos `600`; esa carpeta los ignora en Git. El artefacto de `output/` continúa redactado y portable. `replay-cuyscout.sh` carga el fixture local, levanta el gateway si hace falta, resuelve el archivo por nombre, lo importa con reemplazo idempotente, prepara la app configurada y ejecuta el replay. Para CI u otra máquina se puede proporcionar el mismo mapa explícitamente con `CUYSCOUT_REPLAY_VALUES='{"1.text":"..."}'`.

Para integraciones que necesiten invocar las operaciones por separado, el equivalente HTTP es:

```bash
IMPORTED=$(curl -sf -X POST http://127.0.0.1:4723/artifacts/import \
  -H 'Content-Type: application/json' \
  --data-binary @output/escenario.cuyscout.json)
SESSION=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionID"])' <<<"$IMPORTED")
curl -sf -X POST "http://127.0.0.1:4723/artifacts/${SESSION}/replay" \
  -H 'Content-Type: application/json' -d '{"resetApp":true}'
```

`POST /artifacts/import` valida el esquema `cuyscout.session-artifact.v1` y guarda la grabación, el dispositivo, el driver, el bundle ID y sus metadatos en el almacén local. La disponibilidad del simulador se comprueba al hacer replay. Usa `?overwrite=true` para reemplazar una copia con el mismo ID. Para grabaciones redactadas puedes proporcionar variables por ruta, como `"1.text"` o `"5.expected"`, usando los índices cero-based del script exportado; `redacted` y `text` siguen disponibles como fallbacks globales.

El dispositivo original **no tiene que existir**: CuyScout prefiere ese simulador si está disponible y, si no, elige otro compatible. Para fijar el destino envía `deviceID`. `POST /artifacts/ID/replay/preflight` acepta el mismo cuerpo que `/replay` y devuelve el simulador elegido, avisos y errores sin ejecutar pasos. Si la app no está instalada en el destino, proporciona `appPath` (`.app` de simulador o `.ipa` compatible) con el mismo bundle ID. Se aceptan `optimized`, `resilient` y `variables` igual que en el replay de una sesión activa.

`preparation` admite `preserve` (usar la app abierta si existe, sin limpiar datos), `restart` (valor por defecto: reiniciar proceso, conservar datos y llavero) y `reinstall` (exige `appPath`, desinstala y reinstala la app; limpia su contenedor, **no** el llavero compartido del simulador). El antiguo `resetApp` sigue aceptado por compatibilidad: `true` equivale a `restart` y `false` a `preserve` cuando no se envía `preparation`. La respuesta contiene `success`, `executedSteps`, `totalSteps`, `failedStep`, `error` y duración; un fallo de pasos devuelve HTTP 200 con `success: false`, y los errores de preparación devuelven un error HTTP. `POST /artifacts/ID/restore` sigue restaurando solo metadata. Para listar las pruebas guardadas usa `GET /artifacts/catalog`.

En un proyecto actualizado con `cuyscout init`, `scripts/replay-cuyscout.sh` hace el preflight automáticamente. Puedes elegir destino y modo con `CUYSCOUT_REPLAY_DEVICE_ID=UDID` y `CUYSCOUT_REPLAY_PREPARATION=reinstall`; este último requiere `CUYSCOUT_REPLAY_APP_PATH=/ruta/MiApp.app`.

Si una aserción o búsqueda falla por un aviso reconocido de **guardar contraseña** (español/inglés), CuyScout pulsa exclusivamente un botón de rechazo conocido, por ejemplo «Ahora no»/«Not Now», y reintenta una vez ese paso sin modificar la prueba guardada. El resultado incluye `dismissedInterruptions`. Las alertas desconocidas y las acciones con efectos (toques, escritura, transferencias) no se reintentan automáticamente: se informa el fallo para evitar duplicar una operación. Nunca se pulsa «Guardar» de forma automática. El runner XCTest debe recompilarse para usar esta capacidad.

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

### Almacenamiento y limpieza

La app de macOS incluye **Almacenamiento**: muestra el tamaño de los artefactos persistidos en el gateway y los datos de cada simulador que informa CoreSimulator. Permite eliminar artefactos individuales, simuladores apagados y, tras revisar una confirmación, los simuladores apagados cuyo nombre contiene `Bench` o `Benchmark`. No se elimina nada automáticamente. Los simuladores encendidos o asignados a sesiones activas quedan protegidos; al borrar un artefacto del gateway no se borran las copias exportadas en proyectos. La eliminación de simuladores y artefactos del gateway es permanente.

También se puede inspeccionar desde terminal con `GET /artifacts/status` y `GET /storage/simulators`. Para limitar el crecimiento futuro del gateway, inicia el servidor con `CUYSCOUT_ARTIFACT_RETENTION=100` (o el límite de cantidad que prefieras); la poda se realiza al guardar un nuevo artefacto. Esta opción no controla el espacio de simuladores, los archivos exportados en `output/` ni las compilaciones de Xcode.

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

Para un agente que solo tendrá acceso a herramientas, configura el MCP conectado al
gateway HTTP (el operador prepara Xcode, simulador y runner una vez):

```bash
# Proceso del gateway, desde el proyecto con el runner precompilado:
swift run cuyscout 4723
# En la configuración del cliente MCP, otro proceso:
CUYSCOUT_GATEWAY_URL=http://127.0.0.1:4723 .build/debug/cuyscout-mcp
```

Registra el binario con ruta absoluta y `CUYSCOUT_GATEWAY_URL` en el entorno del
servidor MCP. Para medir tráfico, esa URL debe apuntar al proxy medidor. Si el
gateway exige autenticación, configura también `CUYSCOUT_TOKEN`. El proceso MCP
necesita permiso de red hacia el gateway; el agente no necesita shell ni archivos.
Reinicia el servidor MCP del cliente después de actualizar el binario.

Para pruebas desde una terminal sin cliente MCP nativo, `Scripts/mcp_call.py`
encapsula únicamente el transporte y la serialización JSON-RPC (sin navegación,
selectores ni reintentos automáticos):

```bash
python3 Scripts/mcp_call.py --gateway http://127.0.0.1:4723 --method tools/list
python3 Scripts/mcp_call.py --gateway http://127.0.0.1:4723 --tool cuyscout_help --args '{}'
```

El proceso necesita permiso de red local. Los argumentos son solo el objeto de la
herramienta, sin escribir manualmente el sobre JSON-RPC. En producción se mantiene
la conexión MCP nativa descrita arriba. Un JSON-RPC inválido devuelve `-32700` y
no ejecuta esa petición; un argumento mal tipado identifica su campo sin exponer
el texto introducido.

`initialize.instructions` y `cuyscout_help` describen el flujo y ejemplos completos.
El catálogo del modo gateway ofrece estado, diagnóstico, dispositivos, creación
con `appPath` (.app/.ipa), timeouts, readiness, observe, execute, validación,
exportación TypeScript y cierre con `cuyscout_end_session`. Todas esas herramientas
operan sobre el mismo motor y runner HTTP. El resto de las herramientas y recursos
locales no se anuncia en ese modo, para evitar mezclar sesiones de motores distintos.

El agente lee `structuredContent` (idéntico al JSON en `content[0].text`), copia
`actions[i].action` al ejecutar y valida `texts`, una lista de cadenas. La
observación MCP está desenvuelta; por HTTP está dentro de `value`. Los resultados
MCP que son arrays o escalares se representan como `{ "value": ... }`.
Los fallos de herramientas devuelven `isError: true`, mantienen el ID de petición
y explican la recuperación. `GET /agent-help`, anunciado en `/status`, expone la
misma ayuda para clientes HTTP. La ruta nativa TLS del servidor aún no expone el
flujo completo; usa HTTP local o un proxy TLS que enrute al gateway HTTP.

Sin `CUYSCOUT_GATEWAY_URL` se conserva el motor MCP local y el catálogo completo;
requiere integrar el puente XCTest manualmente y rechaza `appPath` explícitamente.
La exportación genera código, pero el agente debe parametrizar los valores redactados,
añadir las aserciones del objetivo y comprobar la ejecución antes de afirmar éxito.

Verificación del contrato sin simulador: después de `swift build`, ejecuta
`python3 Tests/Conformance/mcp_agent_contract.py`. Utiliza un gateway simulado y
comprueba descubrimiento, ejecución, exportación, cierre y errores. No sustituye
una nueva evaluación de Luna con herramientas únicamente.

## Próximos pasos recomendados

1. Añadir helpers de búsqueda por `accessibility identifier`, label y predicate en el runner.
2. Reemplazar el servidor HTTP mínimo por Vapor o Hummingbird si se necesita concurrencia, autenticación y WebDriver W3C completo.
3. Completar la matriz de verificación en distintos modelos de iPhone físico y versiones de iOS; las acciones nativas usan XCTest/XCUITest firmado y permisos de desarrollo.

---

## 👨‍💻 Autor

**Oswaldo Leon** — oswaldo.leon9@gmail.com

## 💛 Patrocinar

¿Te resultó útil CuyScout? Considera patrocinar el proyecto:

[![PayPal](https://img.shields.io/badge/PayPal-Donate-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/oslh01)

CuyScout es código abierto y gratuito. Tu apoyo ayuda a mantener el proyecto, añadir
nuevas capacidades y seguir bajando el coste de automatizar apps iOS con agentes.
