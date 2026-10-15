# CuyScout Android bridge

Instrumentación con UiAutomator, sin Appium server. Usa el mismo gateway y los mismos
`BridgeCommand`/`BridgeResult` que el runner iOS. El registro de drivers es el paso 3;
la negociación y apertura de sesiones Android del producto corresponde al paso 5.

## Compilar y probar

Requiere JDK 17, Android SDK platform 35 y build-tools 35.0.0. El wrapper fija Gradle 8.9
con checksum; AGP es 8.7.3 y UiAutomator 2.3.0. Soporta Android 8 (API 26) o posterior.

```sh
export JAVA_HOME=/ruta/al/jdk17
export ANDROID_HOME=/ruta/al/sdk
sdkmanager 'platforms;android-35' 'build-tools;35.0.0'
Scripts/build_android_runner.sh
```

Se generan `host/build/outputs/apk/debug/host-debug.apk` y
`host/build/outputs/apk/androidTest/debug/host-debug-androidTest.apk`. Los tests JVM de
`:core:test` usan un backend simulado y un servidor HTTP local; no necesitan emulador.
CI compila ambos APK y ejecuta esos tests. El fixture `runner-tree.json` se comparte
con el test Swift que verifica textos y sugerencias mediante `observe`.

El launcher instala ambos APK automáticamente. Puede recibir rutas explícitas mediante
`CUYSCOUT_ANDROID_HOST_APK` y `CUYSCOUT_ANDROID_TEST_APK`. El empaquetador macOS incluye
los APK si ya están compilados; Android es opcional para compilar la app iOS/macOS.

## Arranque y conexión

`RunnerLaunching` separa los lanzadores iOS y Android del motor. Android instala los APK,
prepara una configuración privada por sesión, y arranca:

```sh
adb -s SERIAL shell am instrument -w \
  -e class com.cuycoders.cuyscout.runner.ScoutBridgeTest \
  -e cuyscoutConfig /data/local/tmp/cuyscout-UUID.json \
  com.cuycoders.cuyscout.host.test/androidx.test.runner.AndroidJUnitRunner
```

El archivo contiene `url`, `sessionId`, `bundleId` (package Android), `maxSeconds` (600)
y, si aplica, `token`. El launcher lo copia con modo 0600; el runner lo lee con la identidad
shell de UiAutomation y lo elimina. No se pasan tokens por argumentos ni se imprimen
selectores, texto ingresado, contenido de capturas o errores de la app en logs.

- Emulador: gateway en `10.0.2.2`, conservando el puerto.
- Físico USB: `adb reverse tcp:PUERTO tcp:PUERTO`, gateway en `127.0.0.1`.
- Físico Wi-Fi: serial TCP/mDNS o `CUYSCOUT_ANDROID_TRANSPORT=wifi`. Requiere
  `CUYSCOUT_BIND_ADDRESS`, `CUYSCOUT_DEVICE_GATEWAY_URL` alcanzable y `CUYSCOUT_TOKEN`.
- Al detener, se termina la instrumentación remota, se borra la config y se retira el reverse
  creado para la sesión. No se desinstala la app bajo prueba.

El runner registra `POST /session/ID/bridge` con cuerpo vacío, sondea comandos cada 200 ms
(GET con timeout de 5 s) y publica resultados (POST con timeout de 20 s). Bearer se aplica
a todas las peticiones. No sigue redirecciones. Un resultado cuya entrega falla se conserva
y reintenta sin ejecutar otra vez la acción. 401/403 detienen el runner; 404 cierra la sesión.

## Árbol y acciones

El backend toma snapshots de accesibilidad directamente; no ejecuta `dumpWindowHierarchy`
por cada observación. Mantiene un cache corto de 50 ms e invalida tras mutaciones. Recorre
ventanas por capa/ID y nodos en preorden estable. Exporta roles normalizados, frames en dp,
`resource-id` sin prefijo de package (o testTag de Compose), `label` desde contentDescription
o text y `value` de campos/controles seleccionables. En Compose se requiere
`testTagsAsResourceId` para poder buscar por testTag.

Se descartan contenedores anónimos no interactivos. Se respetan visibleOnly, interactiveOnly,
maxElements, includeSystemAlerts e hittableOnly. Las ventanas superiores, teclado y hermanos
posteriores con contenido visible pueden ocultar controles; no se ofrecen para tocar. Las alertas de
sistema enfocadas (permissioncontroller/packageinstaller/Android/SystemUI) se incluyen solo
cuando se piden, con `activeAlert`. El comportamiento de capas, OEM, teclados, WebViews,
campos seguros y clipboard necesita prueba real en los dispositivos elegidos.

Implementa búsqueda simple/múltiple y relativa, tap/type/clear/submit/doubleTap/longPress,
atributos y propiedades, displayed/enabled/selected/name/rect/screenshot, waitFor/assertions,
árbol/opciones/diff (snapshot completo, como iOS), tap/type/scroll/screenshot/screenStatic,
sequence y clipboard. Los gestos convierten dp a píxeles solo al ejecutarse.

Los selectores semánticos aceptan identifier (también con prefijo de package), label, value
y type. XPath opera sobre roles normalizados con atributos identifier/label/value/class/
resource-id/text/content-desc/enabled; por ejemplo `//button[@identifier='login']`.
CSS nativo admite roles, `#id`, atributos exactos, descendientes y `>`; no es un DOM WebView.
`predicate` y sintaxis no implementada devuelven error 7 (unsupported), nunca una emulación
de NSPredicate. Error 8 es no such element; 10/11 son element not interactable. Los errores
no incluyen el contenido de los selectores o los valores esperado/actual.

`waitFor` sondea de nuevo (0–25 s). El core usa un presupuesto cooperativo de 25 s y las secuencias
comprueban el límite antes de seguir para evitar toques tardíos; profundidad máxima 16,
100 acciones por secuencia. El gateway conserva su timeout de puente de 30 s por defecto. Las llamadas nativas bloqueantes
dependen además del sistema operativo.

La prueba real de AVD y sus correcciones están en
[Scripts/evidence/run-20261015-android/RESULTADOS.md](../../Scripts/evidence/run-20261015-android/RESULTADOS.md).
La validación física/OEM sigue pendiente por falta de dispositivo.

## Repetir la prueba de humo

`:smokeapp` es una app offline con usuario `demo`, importe `12.50` y comprobante fijo
`DEMO-0001`. No usa cuentas ni pagos reales. Compila con
`./gradlew :smokeapp:assembleDebug` desde este directorio e inicia un gateway con
`CUYSCOUT_AUTORECORD=true` y `CUYSCOUT_ARTIFACT_DIR=/tmp/android-artifacts`.
Con el AVD o físico online/autorizado:

```sh
python3 Scripts/smoke_android_device.py --serial SERIAL \
  --artifacts /tmp/android-artifacts --output /tmp/android-smoke
```

Ejecuta este comando desde la raíz del repositorio con `ANDROID_HOME` configurado.
Comprueba readiness, cinco pantallas mediante observe, aserción del comprobante, grabación,
exportación TypeScript/Maestro y los tres modos de replay nativo. Los valores ficticios
para sustituir la redacción del exportador quedan en `replay-values.json`.
