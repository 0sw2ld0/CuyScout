# Encargo: soporte de Android en CuyScout (emuladores y dispositivos físicos)

Documento para un agente que va a implementarlo. Está escrito contra el código de `main` en
v0.1.1; las rutas y los nombres son reales. Léelo entero antes de tocar nada.

## 1. Objetivo y criterio de éxito

CuyScout automatiza apps iOS sin su código fuente: un agente observa la pantalla, decide,
actúa y deja una prueba reproducible. Hay que conseguir **lo mismo en Android**, en
**emulador (AVD) y en dispositivo físico**, sin duplicar el producto.

El proceso debe ser agnóstico a la tecnología: la misma sesión, la misma `observe`, la misma
grabación y los mismos exportadores, con un driver distinto por debajo.

**Está terminado cuando, sin tocar el flujo del agente:**

1. `POST /session` con una capability de Android abre una sesión en un emulador y en un
   dispositivo físico.
2. `GET /session/{id}/observe` devuelve `actions` y `texts` con la misma forma y el mismo
   coste en tokens (orden de magnitud) que en iOS.
3. El escenario `login → pagar → comprobante` de una app Android de prueba corre de punta a
   punta, queda grabado y se exporta a Appium TypeScript y a Maestro.
4. Los 389 tests actuales siguen pasando y los nuevos cubren el driver con un doble, sin
   necesitar un emulador en CI.

## 2. Lo que NO debes hacer

- **No fork del producto ni un segundo gateway.** Todo entra por el gateway existente.
- **No renombrar ni cambiar el significado de lo que ya usa iOS** (`ScoutAction`,
  `ScoutSelector`, formato de los `.cuyscout.json`). Los artefactos grabados en iOS deben
  seguir cargando. Solo se **añade**.
- **No reemplazar el puente por Appium/UiAutomator2 server como dependencia obligatoria.**
  Es una opción de implementación del runner (ver §5), no del contrato.
- **No guardes credenciales ni datos personales** en fixtures, lecciones ni logs
  (`LessonRedactor` ya redacta; respétalo).

## 3. Cómo está hecho hoy (y dónde cortar)

```
Agente ──HTTP W3C / MCP──► Gateway (CuyScout, un proceso Swift)
                              │  ScoutEngine: sesiones, observe, grabación, replay, lecciones
                              │
              CuyScoutDriver.execute(ScoutAction, on: Device)      ← control del host
                              │  SimulatorController: simctl / devicectl
                              │
              Puente (JSON/HTTP, el runner SONDEA al gateway)      ← control dentro del dispositivo
                              │  GET  /session/{id}/bridge/command  → BridgeCommand{id, action}
                              │  POST /session/{id}/bridge/result   ← BridgeResult{commandID, success, payloadBase64, error, errorCode}
                              ▼
                    Runner XCTest en el iPhone (Runner/ScoutRunner)
```

Hay **dos canales** y los dos tienen que existir para Android:

| Canal | iOS hoy | Qué es | Android |
|---|---|---|---|
| **Host** | `SimulatorController` vía `xcrun simctl` / `devicectl` | Arrancar dispositivos, instalar, lanzar, permisos, GPS, capturas, deep links | `AndroidController` vía `adb`, `emulator`, `avdmanager` |
| **Puente** | Runner XCTest que sondea `bridge/command` | Buscar y tocar elementos, escribir, leer el árbol de accesibilidad | Runner Android (instrumentación con UiAutomator) que sondea **el mismo** `bridge/command` |

El contrato del puente es JSON sobre HTTP y **no menciona a Apple**; es el punto de apoyo
del diseño. Implementa el runner de Android contra ese contrato y todo lo que hay encima
(observe, grabación, replay, exportadores, lecciones, detección de bucles) funciona sin
cambios.

### Archivos que debes leer primero

| Archivo | Por qué |
|---|---|
| `Sources/CuyScoutCore/DriverAPI.swift` | `CuyScoutDriver`, `DriverDescriptor`, `DriverRegistry`; los dos adaptadores iOS que debes imitar |
| `Sources/CuyScoutCore/SimulatorController.swift` | Cómo se traduce cada `ScoutAction` al host (≈390 líneas) |
| `Sources/CuyScoutCore/Models.swift` (`ScoutAction` ~l.158, `ScoutSelector` ~l.1224, `BridgeCommand`/`BridgeResult` ~l.397) | El vocabulario compartido |
| `Runner/ScoutRunner/ScoutRunner/ScoutBridgeRunner.swift` | El runner iOS: bucle de sondeo (l.~87), `execute` (l.~99), `query(for:)`, `accessibilityTree`, `snapshotProperties` (l.~522) |
| `Sources/CuyScoutCore/ScoutEngine.swift` (`createSession` ~l.491, `observe` ~l.1768, `launchRunner` ~l.836) | Dónde el motor llama al driver y al runner |
| `Sources/CuyScoutCore/PhysicalGateway.swift` | Por qué un dispositivo físico necesita que el gateway sea alcanzable por red |
| `Sources/CuyScout/HTTPServer.swift` (rutas `bridge`, ~l.410) | El lado servidor del puente |
| `Tests/CuyScoutCoreTests/ScoutEngineTests.swift` (`TestDriver`, ~l.1707) | Cómo se prueba un driver sin dispositivo |

## 4. Mapa del acoplamiento a iOS

Esto es lo que hay que desacoplar o ampliar. Está ordenado de menor a mayor esfuerzo.

### 4.1 Ya es neutral: no lo toques

- `ScoutAction`: `tap`, `swipe`, `type`, `tapElement`, `typeElement`, `waitFor`,
  `assertVisible`, `assertText`, `findElement(s)`, `screenshot`, `accessibilityTree*`,
  `sequence`, `scroll`, `clearElement`, `setClipboard`, `rotate`, `openURL`, `deepLink`…
- `ScoutSelector.Strategy`: `accessibilityIdentifier`, `label`, `value`, `type`, y los
  pasos de `xpath`/`cssSelector`.
- El puente (`BridgeCommand`/`BridgeResult`), el WebSocket de eventos, la grabación, las
  lecciones, la detección de bucles (`canonicalActionSignature`) y la cola de sesiones.
- La forma de `observe`: `actions` (con selector semántico) y `texts`.

### 4.2 Es iOS pero está aislado en un sitio: se amplía

| Dónde | Qué asume iOS | Qué hacer |
|---|---|---|
| `Models.swift` · `Device` | Solo `kind: simulator \| physical`; no hay plataforma | Añadir `platform` (`ios` por defecto, `android`). Es **aditivo** y con valor por defecto para no romper artefactos antiguos. Un AVD es `kind: simulator`. |
| `Models.swift` · `Session`, `ScoutAction.launch(bundleIdentifier:)` | El id de la app se llama `bundleIdentifier` | Mantén el nombre del campo (compatibilidad) y documenta que en Android es el `applicationId`/package. Para elegir la actividad, añade un campo opcional, no cambies el existente. |
| `ScoutEngine.createSession` (l.~491-492) | `driverID` por defecto `"ios-simulator"`; `requiredKind` se deduce comparando con `"ios-device"`/`"ios-simulator"` | Generaliza: el driver declara qué `kind` sirve. Añade los ids `android-emulator` y `android-device`. |
| `ScoutEngine` (l.~182, ~280, ~336) | Listas literales `["ios-simulator","ios-device"]` para decidir si un replay es válido y mapear `kind` → driver | Sustituir por una consulta al `DriverDescriptor` (p. ej. un `platform` y un `deviceKind` en el descriptor). |
| `ScoutEngine.sessionCapabilities` (l.~488) | Devuelve `"platformName": "iOS"` | Que lo tome del `Device`. |
| `CapabilityNegotiator` (l.~21) | Lista de alias `appium:*` pensada para iOS (`xcodeOrgId`, `xcodeSigningId`, `wdaLocalPort`, `usePrebuiltWDA`, `updatedWDABundleId`, `showXcodeLog`, `webDriverAgentPort`) | Aceptar los de Android (`appium:appPackage`, `appium:appActivity`, `appium:avd`, `appium:udid`) y descartar con aviso los de iOS que no apliquen en una sesión Android. |
| `DriverDescriptor.platforms` | `["iOS"]` | `["Android"]` para los nuevos; el registro ya soporta varios drivers. |

### 4.3 Es iOS y está repartido: hay que decidir

- **Vocabulario de tipos de elemento.** `ScoutEngine.visibleTexts` filtra por
  `statictext`, `textfield`, `securetextfield`, `textview`, `searchfield`, `link`, `alert`,
  e `isInteractiveType` decide qué es accionable; ambos esperan nombres tipo XCUIElement.
  **Decisión recomendada:** el runner de Android **normaliza** al mismo vocabulario
  (`android.widget.Button` → `button`, `EditText` → `textfield`, `TextView` → `statictext`,
  `CheckBox`/`Switch` → `switch`, `ImageView` → `image`…). Es lo más barato y no toca el
  motor. La alternativa (un enum de roles neutral en el core) es más limpia pero cambia el
  motor y los artefactos; si la eliges, hazlo en un PR aparte.
- **`isSymbolName`.** Filtra nombres de SF Symbols (`arrow.left.circle.fill`) de los
  `texts`. En Android no existen; no hace falta nada, pero **sí** hay un equivalente a
  vigilar: `contentDescription` de iconos con nombres internos (`ic_arrow_back`). Medir antes
  de filtrar.
- **Selector `predicate`.** Es `NSPredicate` en iOS. En Android no hay equivalente directo.
  No lo emules: devuelve `ScoutError.unsupported` con un mensaje claro y deja que el agente
  use `accessibilityIdentifier`/`label`/`xpath`.
- **Mapeo de `accessibilityIdentifier`.** En Android el equivalente fiable es el
  `resource-id` (y, para Compose, `testTag` expuesto como resource-id con
  `testTagsAsResourceId`). `contentDescription` corresponde a `label`. Documenta esa
  convención; es la decisión que más afecta a la calidad de las pruebas.

### 4.4 Es iOS de verdad: capacidades que no existen o difieren

Para cada una, el driver de Android debe **responder `ScoutError.unsupported` con un mensaje
accionable**, nunca fallar en silencio.

| Acción | iOS (`simctl`) | Android |
|---|---|---|
| `launch` / `terminate` | `simctl launch/terminate` | `adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1` o `am start -n <pkg>/<act>`; `am force-stop <pkg>` |
| `openURL` / `deepLink` | `simctl openurl` | `adb shell am start -a android.intent.action.VIEW -d <url>` |
| `grantPermission` | `simctl privacy` | `adb shell pm grant <pkg> <permiso>` |
| `setLocation` | `simctl location` | `adb emu geo fix <lon> <lat>` (solo emulador) |
| `screenshot` | `simctl io screenshot` | `adb exec-out screencap -p` |
| `setAppearance` | `simctl ui appearance` | `adb shell cmd uimode night yes\|no` |
| `rotate` | `simctl ui orientation` | `adb shell settings put system accelerometer_rotation 0` y `… user_rotation <0-3>` |
| `setClipboard`/`getClipboard` | `simctl pbcopy/pbpaste` | sin API estable por `adb`; vía el runner |
| `startVideoRecording` | `simctl io recordVideo` | `adb shell screenrecord` (límite de 180 s) |
| `pushNotification`, `icloudSync`, `resetKeychain`, `setBiometry`, `setStatusBar`, `setContentSize`, `shake`, `addMedia` | `simctl …` | Sin equivalente directo o muy distinto → `unsupported` al inicio; priorizar `setBiometry` (`adb emu finger touch`) solo si hace falta |
| `getAppContainer`, `enumerateFiles`, `downloadFile`, `uploadFile` | contenedor de datos del simulador | `adb shell run-as <pkg>` (solo apps depurables) / `adb pull`/`push` |

## 5. Plan de implementación (en este orden, un PR por paso)

Cada paso termina con tests en verde y no cambia el comportamiento de iOS.

### Paso 1 — Neutralizar el modelo (sin Android todavía)
- Añade `platform` a `Device` (con valor por defecto `ios`, decodificación tolerante).
- Reemplaza las listas literales `["ios-simulator","ios-device"]` por una consulta al
  descriptor del driver (`platform`, `deviceKind`).
- `sessionCapabilities` toma `platformName` del dispositivo.
- **Prueba de que no rompes nada:** todos los tests actuales + un test que decodifique un
  `.cuyscout.json` grabado antes del cambio.

### Paso 2 — `AndroidController` (canal host)
- Nuevo archivo `Sources/CuyScoutCore/AndroidController.swift`, **simétrico** a
  `SimulatorController`: `devices()`, `installApp`, `uninstallApp`, `isAppInstalled`,
  `boot`/`shutdown` del AVD, `execute(_:on:)` con la tabla de §4.4.
- Localiza `adb`/`emulator` por `ANDROID_HOME`/`ANDROID_SDK_ROOT`, luego `PATH`, luego la
  ruta por defecto de Android Studio. Si falta, `doctor()` lo dice con el comando a ejecutar
  (como hace hoy para `xcrun`).
- Lista dispositivos con `adb devices -l` (físicos y emuladores en marcha) y AVD apagados con
  `emulator -list-avds`. El `Device.id` es el serial de `adb`; un AVD apagado usa el nombre.
- Distingue físico de emulador por el prefijo `emulator-` del serial o por
  `ro.kernel.qemu`.
- **Todas las llamadas a procesos pasan por un único punto inyectable** (como
  `run(_:_:)`/`Self.execute` en `SimulatorController`) para poder probar con un doble.

#### Convenciones del controlador host (paso 2)

- `AndroidController` acepta un ejecutor inyectable que recibe ejecutable, argumentos,
  modo (`wait` o `background`) y, para subir archivos privados, un archivo de entrada.
  Todas las invocaciones, incluidas las de arranque y video, pasan por ese ejecutor.
- `boot(deviceID:)` acepta el nombre del AVD apagado y devuelve el `Device` con su serial
  `adb` cuando `sys.boot_completed=1`. Usa ese serial para las operaciones posteriores.
- `bundleIdentifier` significa package/applicationId en Android. La acción `launch` usa
  la actividad launcher; `launchApp(_:activity:on:)` permite elegir una actividad sin
  cambiar el formato de `ScoutAction`.
- Las rutas de archivos del dispositivo son absolutas. `/data/data/<package>/…` y
  `/data/user/0/<package>/…` usan `run-as`, solo para apps depurables. Los archivos compartidos
  usan `adb pull`/`push`. Las transferencias privadas usan `adb shell -T` para conservar
  bytes y propagar el código de salida; no se utiliza una PTY.
- El video se graba hasta 180 segundos en un archivo temporal del dispositivo. Al detener,
  se comprueba la identidad del proceso antes de enviar SIGINT y se copia el MP4 a la ruta
  local solicitada antes de borrar el temporal. Si falla la copia, puede reintentarse.
- `doctor()` permite usar solo platform-tools con un físico; emulator y avdmanager son
  opcionales en ese caso. Informa de dispositivos `unauthorized` y `offline`, con los pasos
  para recuperarlos. Su integración en el diagnóstico del gateway corresponde al paso 3.
- Las pruebas de este paso usan salidas representativas de las herramientas con seriales
  ficticios. No sustituyen la prueba de humo en AVD y físico del §7.4.

Referencias de comandos: [adb](https://developer.android.com/tools/adb),
[opciones de shell de adb](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md),
[emulator](https://developer.android.com/studio/run/emulator-commandline).

### Paso 3 — Drivers
- `AndroidEmulatorDriverAdapter` (`android-emulator`) y `AndroidDeviceDriverAdapter`
  (`android-device`), análogos a `SimulatorDriverAdapter`/`PhysicalDeviceDriverAdapter`.
- Regístralos en `ScoutEngine.init` junto a los de iOS.
- `health()` informa de `adb` y del SDK; `doctor` se amplía con los chequeos de Android.

#### Registro y diagnóstico de drivers (paso 3)

- `ScoutEngine` registra los cuatro drivers. Ambos adaptadores Android comparten el mismo
  `AndroidController`, que puede inyectarse en el inicializador del motor para probarlos.
  Rechazan plataforma o tipo de dispositivo incompatibles antes de ejecutar comandos.
- `health()` diagnostica el canal host: informa de adb y SDK, y el driver de emulador exige
  además `emulator`. El driver físico permite adb por PATH sin exigir el SDK completo,
  emulator ni avdmanager. Los errores de conexión y autorización se propagan al diagnóstico.
- `ScoutEngine.doctor()` añade los chequeos `android_*` y sus recomendaciones. Conserva el
  significado de `ready` para iOS: Android es opcional para ese resultado. Consulta
  `driverHealth()` para la disponibilidad de cada driver Android.
- Este registro no habilita todavía la negociación de capabilities Android ni la apertura
  de sesiones sobre esos dispositivos: esa integración corresponde al paso 5. El runner
  corresponde al paso 4. Los descriptores anuncian solo las capabilities comunes de
  selección; las específicas de app/actividad/AVD se añadirán con la negociación.

### Paso 4 — Runner Android (canal puente)
Es la pieza grande. **Implementa el contrato de §6, no una tecnología concreta.**

- Ubicación: `Runner/AndroidRunner/` (proyecto Gradle), con un APK de instrumentación y un
  APK objetivo mínimo, igual que `ScoutHost` + `ScoutRunner` en iOS.
- Tecnología recomendada: **UiAutomator** (`androidx.test.uiautomator`) dentro de un test
  instrumentado. Ve la app y los diálogos del sistema (permisos), que es lo que necesita el
  agente; Espresso no.
- Bucle: registrar el puente → sondear `GET /session/{id}/bridge/command` → ejecutar →
  `POST …/bridge/result`. Mismo ritmo y mismos tiempos de espera que el runner iOS.
- Arranque: `adb shell am instrument -w <runner>/androidx.test.runner.AndroidJUnitRunner`,
  lanzado desde `launchRunner` (hoy invoca `xcodebuild test-without-building`). Extrae esa
  parte detrás de una pequeña interfaz por plataforma en lugar de bifurcar con `if`.
- **Alcanzar el gateway desde el dispositivo:**
  - Emulador: el host es `10.0.2.2`.
  - Físico por USB: `adb reverse tcp:<puerto> tcp:<puerto>` y el runner usa
    `127.0.0.1`. Es más simple y seguro que el modo de red local de iOS
    (`PhysicalGateway`), y evita exponer el gateway en la LAN.
  - Físico por Wi-Fi: reutiliza `CUYSCOUT_BIND_ADDRESS` y `CUYSCOUT_DEVICE_GATEWAY_URL`
    (ya existen) con el token obligatorio.
- Acciones mínimas a implementar (las que implementa hoy el runner iOS, ver `execute`):
  `findElement(s)`, `findElement(s)FromElement`, `tapElement`, `typeElement`,
  `clearElement`, `submit`, `doubleTap`, `longPress`, `elementAttribute`
  (`label|value|identifier|enabled|exists`), `elementDisplayed`, `elementEnabled`,
  `elementRect`, `elementSelected`, `elementName`, `elementScreenshot`, `waitFor`,
  `assertVisible`, `assertText`, `accessibilityTree{,WithOptions,Diff}`, `tap`, `type`,
  `scroll`, `screenshot`, `screenStatic`, `sequence`.
- **`errorCode` 8 = "no such element"**: el motor lo traduce a un error W3C concreto
  (`Models.swift`, comentario de `BridgeResult`). Respétalo.

#### Implementación y verificación del runner (paso 4)

- Proyecto Java/Gradle en `Runner/AndroidRunner/`: core JVM comprobable sin Android, APK
  host y APK de instrumentación UiAutomator. Compilar con `Scripts/build_android_runner.sh`
  (JDK 17, platform/build-tools 35, Android mínimo API 26).
- `RunnerLaunching` separa el arranque por plataforma. Android instala los dos APK, transfiere
  configuración privada y arranca `AndroidJUnitRunner`. USB utiliza reverse y emulador
  `10.0.2.2`; Wi-Fi exige URL, bind y token. El borrado de sesión detiene instrumentación
  y limpia los recursos de conexión.
- El core mantiene el contrato de errores y respuestas, normaliza roles e identificadores,
  filtra el árbol y convierte gestos dp a píxeles en el backend. Hay pruebas JVM de acciones,
  selectores, filtros, geometría y transporte HTTP, además del fixture compartido con Swift.
  El código 7 ahora se traduce a `ScoutError.unsupported` en el gateway; el 8 conserva
  `no such element`.
- El registro real del puente es **POST `/session/{id}/bridge` con cuerpo vacío**. El código
  manda frente a cualquier referencia histórica a `/bridge/register`; no se añade otra ruta.
- Ver detalles de configuración, límites, selectores y compilación en
  [Runner/AndroidRunner/README.md](../Runner/AndroidRunner/README.md). La prueba real de AVD/
  físico, los casos OEM y la medición de tokens siguen pendientes; CI valida core y APK sin
  emulador. La apertura/negociación de sesiones Android continúa en el paso 5.

### Paso 5 — Sesión, readiness y replay
- `createSession` con `appium:platformName: Android` debe seleccionar el driver correcto.
- `SessionReadiness`: hoy el motor usa el bloqueador `xctest_runner_starting` y el campo
  `xctestBridgeConnected` (`ScoutEngine.swift` ~l.1968, `Models.swift` ~l.539). Son parte de la
  API que leen los agentes y las guías: **conserva ambos nombres** y añade un alias neutral
  (p. ej. `runner_starting`, `bridgeConnected`) en lugar de renombrar.
- El replay nativo ya funciona sobre `ScoutAction`; verifica que `preparation`
  (`preserve|restart|reinstall`) se traduce: `restart` = `am force-stop` + `am start`;
  `reinstall` = `pm clear` (borra datos) o desinstalar/instalar.

#### Integración y verificación de sesiones (paso 5)

- `POST /session` acepta `platformName` o `appium:platformName` = `Android`, con aliases
  `appPackage`, `appActivity`, `avd` y `udid` (también `appium:*`). El driver se resuelve
  por descriptor y tipo del dispositivo; un serial físico selecciona `android-device`.
  `appium:driverId` permite elegirlo explícitamente y se valida contra la plataforma.
- `appium:app` exige un APK local y `appium:appPackage`; sin APK se usa la app instalada.
  `bundleIdentifier` sigue significando package/applicationId. `Session.appActivity` es
  opcional y sobrevive al artefacto/restauración. Las respuestas anuncian Android,
  UiAutomator2, appPackage y appActivity; conservan bundleId como alias de compatibilidad.
  Las capabilities de firma/WDA de iOS se descartan y se devuelven avisos sin sus valores
  en `cuyscout:capabilityWarnings`.
- Se reserva el AVD antes de arrancarlo; la reserva se transfiere a su serial adb y se
  libera si falla el arranque. La selección y preparación Android no requieren Xcode,
  firma Apple, Rosetta ni modo iPhone. USB mantiene `adb reverse`; Wi-Fi conserva sus
  requisitos de bind/URL/token del paso 4.
- Readiness conserva `xctestBridgeConnected` y `xctest_runner_starting`, y añade
  `bridgeConnected` y `runner_starting`. Ambos campos indican registro del puente;
  `interactionReady` exige además que el runner haya comenzado a sondear.
- Replay `preserve` conserva datos/proceso; `restart` fuerza el cierre y arranca la
  actividad con el runner; `reinstall` sin APK usa `pm clear`, con APK desinstala/instala.
  `noReset` conserva la app y `fullReset` limpia sus datos al abrir una sesión Android.
- Verificación sin dispositivo: `swift test`, `Scripts/build_android_runner.sh` y
  `python3 Scripts/test_android_sessions.py .build/debug/cuyscout`. La última prueba
  ejecuta el gateway HTTP real con un adb simulado, graba y reproduce en ambos tipos de
  dispositivo con los tres modos, sin reescribir el artefacto original. También corre en
  CI. La prueba real en AVD/físico del §7.4 continúa pendiente.

### Paso 6 — Exportadores
- `TypeScriptReplayExporter.swift`: hoy fija `platformName: 'iOS'`,
  `'appium:automationName': 'XCUITest'` y capabilities de WebDriverAgent. Hay que emitir
  según la plataforma de la sesión: `UiAutomator2`, `appium:appPackage`,
  `appium:appActivity`/`appium:intentAction`, `appium:noReset`. El resto (`remote()`,
  `find`, el bucle de `run`) se reutiliza.
- `MaestroFlowExporter.swift`: ya emite `appId` a partir de `session.bundleIdentifier`, y
  Maestro usa la misma clave para el package de Android; verifica la salida y los
  `launchApp` con otro `appId`.
- Mantén el contrato de `CUYSCOUT_REPLAY_PREPARATION` y `APPIUM_SESSION_TIMEOUT_MS`
  (se ve en v0.1.1).

#### Exportación por plataforma (paso 6)

- TypeScript recibe el contexto de `Session` al generar grabaciones activas, detenidas,
  redactadas y artefactos; la exportación CLI regenera desde pasos y sesión, también en
  artefactos antiguos. El formato del artefacto no cambia y iOS sigue siendo el valor
  predeterminado cuando falta contexto.
- Android emite UiAutomator2, package/actividad e intent MAIN, sin capabilities de WDA.
  Requiere `ANDROID_UDID`; `ANDROID_APP_PACKAGE` y `ANDROID_APP_ACTIVITY` permiten cambiar
  los datos grabados. Si no se grabó una actividad, pasa `ANDROID_APP_ACTIVITY` o un APK
  en `ANDROID_APP` (ruta accesible desde el servidor Appium). `ANDROID_INTENT_ACTION`
  permite cambiar la acción del intent.
- `CUYSCOUT_REPLAY_PREPARATION` conserva `preserve|restart|reinstall`: noReset conserva los
  datos salvo en reinstall; dontStopAppOnReset conserva el proceso en preserve y
  forceAppLaunch fuerza su reinicio en restart. Reinstall usa la limpieza de datos de
  UiAutomator2 con noReset=false. `APPIUM_SESSION_TIMEOUT_MS` conserva su contrato.
- Los selectores Android usan resource-id/testTag, content-desc/text y valores editables/
  checkable. Predicate y las estrategias no traducibles se rechazan antes de conectar.
  Las coordenadas grabadas en dp se convierten a píxeles con la densidad del dispositivo;
  el XML Android se usa para esperar estabilidad antes de los gestos. El flujo de iOS
  conserva sus selectores, capabilities y cierre de teclado.
- Maestro conserva appId como package Android; hay regresiones para launchApp por defecto,
  el package principal y el lanzamiento de otro package, también dentro de sequence.
- Verificación: `npm ci --prefix Tests/ExporterRuntime --ignore-scripts` y `swift test
  --parallel`. Los TypeScript exactos se compilan y ejecutan con WebdriverIO contra un
  doble W3C para ambas plataformas y los tres modos; el CI instala estas dependencias.
  La prueba HTTP comprueba también exportación activa, artefactos y CLI TypeScript/Maestro.
  No sustituye el replay en Appium/Maestro con un dispositivo real. Otros exportadores
  (Python/Java/XCTest) conservan su comportamiento previo.

### Paso 7 — Superficie del agente y proyecto
- `ProjectScaffolder.swift` genera `scripts/*.sh` con `xcrun` y `.cuyscout-project.json`
  con claves `simulator`/`physical` (instaladores `.app`). Añade `android` con su APK y
  `applicationId`; que `open-session.sh` y `replay-appium.sh` elijan el flujo por plataforma.
- MCP (`Sources/CuyScoutMCP/main.swift`, l.~100): `cuyscout_create_session` se describe como
  «Crea una sesión con ios-simulator o ios-device»; amplía esa descripción y sus propiedades
  (`deviceId`, `bundleIdentifier`, `driverId`) en lugar de crear una herramienta paralela.
- `AGENT-GUIDE.md` y `.claude/skills/cuyscout-ios/SKILL.md`: **no los cambies para decir
  "iOS o Android"**; crea `cuyscout-android` si la guía se desvía, para que `observe` siga
  siendo la lectura barata (esto fue lo que dio el 16×–20× de ahorro: ver §8).

## 6. Contrato del runner (lo único que no puede variar)

**`accessibilityTree` / `accessibilityTreeWithOptions`** devuelve:

```json
{ "elements": [
  { "type": "button",            // vocabulario normalizado de §4.3
    "typeCode": "9",             // opcional, informativo
    "identifier": "btn_login",   // resource-id (sin prefijo de paquete) o testTag
    "label": "Iniciar sesión",   // contentDescription o text
    "value": "",                 // texto de un campo / estado de un switch
    "enabled": true,
    "exists": true,
    "hittable": true,            // solo con hittableOnly
    "frame": { "x": 24, "y": 612, "width": 345, "height": 52 } } ] }
```

- Coordenadas en **puntos independientes de densidad** (dp), no en píxeles, para que
  `tap(x:y:)` y las sugerencias por coordenadas sean consistentes entre dispositivos.
- Orden de documento estable (el motor calcula `stateId` sobre el árbol: si el orden cambia
  entre lecturas sin que cambie la pantalla, la detección de bucles se rompe).
- Respeta `AccessibilityOptions`: `visibleOnly`, `interactiveOnly`, `maxElements`,
  `includeSystemAlerts`, `hittableOnly`. `observe` pide
  `visibleOnly:true, interactiveOnly:false, hittableOnly:true, maxElements:max(maxActions*8, 200)`.
- Un control tapado por otra vista no es `hittable` (el runner iOS tiene
  `coveredOnlyByInvisible`; busca la intención, no copies el algoritmo).

**Cada comando** responde con `BridgeResult`: `success`, `payloadBase64` (binario, p. ej. una
captura) o JSON, `error` y `errorCode`.

## 7. Cómo probarlo (sin depender de un emulador en CI)

1. **Doble de driver**: sigue `TestDriver` en `ScoutEngineTests.swift` (~l.1707) para probar
   sesión, observe, grabación y replay con un driver falso de `platform: Android`.
2. **`AndroidController` con ejecutor inyectado**: alimenta salidas reales de
   `adb devices -l`, `emulator -list-avds` y `pm list packages` como fixtures y prueba el
   análisis (igual que `physicalDevices(from:)` y `simulatorApps(from:)` en iOS).
3. **Contrato del runner**: un test que valide un JSON de árbol de ejemplo contra §6 y pase
   por `visibleTextsForTesting` y `nativeSuggestions`.
4. **Prueba de humo real, manual y documentada**: un AVD arm64 (en Mac Apple Silicon) y un
   dispositivo físico con depuración USB, con el escenario `login → pagar → comprobante`
   sobre una app de ejemplo. Guarda la evidencia en
   `Scripts/evidence/run-<fecha>-android/` como se hizo con la de iOS.
5. **Mide el coste**: repite la medición de §8 con la misma metodología. Si `observe` en
   Android cuesta mucho más que en iOS, el árbol está trayendo ruido que hay que filtrar.

Comandos de verificación que ya existen y deben seguir pasando:

```bash
swift test                              # 389 tests
swift build --product cuyscout-app
Scripts/build_dmg.sh                    # el instalador no debe romperse
```

## 8. Por qué importa el diseño de `observe` (no lo estropees)

La ventaja medida de CuyScout frente a Appium (10×–20× menos tokens por escenario, ver
`README.md`) viene de que `observe` **filtra en el servidor** y responde dos preguntas:
qué se puede tocar y qué dice la pantalla. Si el runner de Android devuelve el árbol crudo
de UiAutomator (cientos de `FrameLayout`/`ViewGroup` anónimos), esa ventaja desaparece.

- Descarta contenedores sin identificador, etiqueta ni valor que no sean accionables.
- Normaliza `text`/`contentDescription` para no duplicar el mismo texto.
- Mide `GET /observe` en tokens (`cl100k_base`) sobre una pantalla real y compáralo con el
  árbol completo. El objetivo es la misma proporción que en iOS (≈7×–12×).

## 9. Riesgos conocidos

| Riesgo | Mitigación |
|---|---|
| UiAutomator es lento con árboles grandes | Pedir solo lo visible; evitar `dumpWindowHierarchy` completo en cada `observe`; cachear dentro del runner |
| Apps con WebView o Compose sin `testTag` expuesto | Documentar la convención de identificadores (§4.3); `collectIdentifierFindings` + `IdentifierBacklog`/`IdentifierReport` ya registran los controles sin identificador y generan el informe (HTML/Markdown/CSV) |
| Fragmentación de fabricantes (diálogos de permisos distintos) | Probar al menos en AVD de AOSP y en un físico de otra marca; `includeSystemAlerts` |
| Autorización de depuración USB en el físico | `doctor` debe detectar `unauthorized` en `adb devices` y decir qué hacer |
| El replay con Appium (UiAutomator2) y el runner propio se comportan distinto | Es el mismo caso que XCUITest vs XCTest en iOS: validar con `replay-appium.sh` y documentar diferencias |
| CI solo tiene macOS | Los tests de §7.1–7.3 no necesitan emulador; el humo real queda manual |

## 10. Entrega

- Una rama y un PR **por paso** de §5, empezando por el 1. Cada PR: descripción con qué
  cambia, qué se verificó y qué **no** se verificó.
- No fusiones tú: deja los PR abiertos con CI en verde.
- Al final, actualiza `README.md` (requisitos de Android, una sección corta) y deja la
  evidencia de §7.4.
- Si algo de este documento no coincide con el código, **el código manda**: corrige el
  documento en el mismo PR y dilo en la descripción.
