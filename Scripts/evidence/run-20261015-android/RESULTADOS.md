# Humo Android — 15 de octubre de 2026

El AVD real completó **login → pagar → comprobante**, con grabación, exportación y replay.
**El físico no se ejecutó**: el usuario confirmó que no tiene un Android físico disponible.
No se considera validado el transporte USB, la autorización de depuración ni otro OEM.

La [revisión del PR #50](REVISION-PR50.md) documenta las correcciones posteriores del
exportador y la protección contra mezclar evidencia de corridas diferentes. Los archivos
de `avd/` conservan la corrida original; `review/` contiene la validación posterior.
La [segunda revisión](SEGUNDA-REVISION-PR50.md) cubre la paridad de `selected`/`checked`
y los falsos positivos del script de humo; sus resultados están en `review-2/`.

## Entorno y alcance

- Mac Apple Silicon; AVD `CuyScout_API35`, AOSP Android 15/API 35, arm64-v8a, imagen r02.
- Android Emulator 37.2.12, platform-tools 37.0.1; pantalla 1080×2400, densidad 420 dpi.
- App offline `com.cuycoders.cuyscout.demo/.MainActivity`, fuente en
  `Runner/AndroidRunner/smokeapp/`. Usuario `demo`, importe `12.50`, operación fija
  `DEMO-0001`. Sin cuentas, red ni dinero reales.
- Runner propio: APK host e instrumentación UiAutomator 2.3.0; gateway Swift real por
  `10.0.2.2:18765`. Sin dobles adb o de puente en estas corridas.
- Comparación: Appium 3.2.2, UiAutomator2 8.7.0, WebdriverIO 10.0.2; Maestro 2.11.0.

## Resultados

| Comprobación | Resultado | Evidencia |
|---|---|---|
| Sesión Android, instalación, readiness y puente real | Pasa | `avd/http.jsonl` |
| Observe de login, inicio, pago, confirmación y comprobante | Pasa | `avd/01-*` a `avd/05-*` |
| Escritura en campos vacíos y aserción exacta de comprobante | Pasa | `avd/http.jsonl`, `avd/receipt.png` |
| Grabación y exportación TypeScript/Maestro | Pasa | `avd/scenario.cuyscout.json`, `avd/replay.ts`, `avd/maestro.yaml` |
| Replay nativo restart / reinstall / preserve | Pasa: 12/12 pasos en cada modo | `avd/native-replay.json` |
| Replay real por script generado `replay-appium.sh`, restart | Pasa, incluida assertText | `avd/appium-replay.log` |
| Replay del YAML exportado por Maestro | Pasa, incluida aserción del comprobante | `avd/maestro-replay.log` |
| Permiso de notificaciones, includeSystemAlerts=false / true | Pasa: 0 / 8 elementos, botones permitir y denegar solo con true | `avd/permission-*.json`, `avd/permission.png` |
| Android físico y compatibilidad OEM | **Pendiente: sin dispositivo** | `physical/status.json` |

Los replays nativos usan `native-replay-source.cuyscout.json`; la captura HTTP final usa
`scenario.cuyscout.json`. Son dos corridas del mismo escenario. Antes de probar preserve
se restableció explícitamente la pantalla inicial: preserve no debe reiniciar por sí solo.
Los valores redactados se suministraron mediante `replay-values.json`, todos ficticios.
`replay.ts` se regeneró desde el artefacto usando el exportador corregido; los artefactos
originales se conservaron como evidencia de lo grabado antes de esa corrección.

## Correcciones encontradas con el dispositivo real

1. **El runner no registraba el puente.** UiAutomation ejecuta el comando sin interpretar
   las comillas como un shell; `cat 'ruta'` buscaba un archivo con comillas en su nombre.
   Ahora usa la ruta validada por la allowlist, cierra un único propietario del descriptor
   y espera que termine la eliminación de la configuración antes de sondear el gateway.
   El error de instrumentación incluye solo el tipo de excepción, sin sus valores privados.
2. **Escribir añadía el placeholder al texto.** `AccessibilityNodeInfo.getText()` puede
   devolver el hint de un EditText vacío. Ahora `isShowingHintText()` evita usarlo como
   valor, y `getHintText()` se conserva como etiqueta cuando falta contentDescription.
3. **Appium llegaba al comprobante pero fallaba assertText.** UiAutomator2 convierte una
   descripción ausente en la cadena `"null"`; el exportador ahora continúa con el texto
   visible. `appium-before-fix.log` conserva el fallo; el runtime de WebdriverIO añade una
   regresión con TextView sin descripción y esa respuesta real de UiAutomator2.
4. El error del gateway sin puente indicaba la ruta inexistente `/bridge/register` y
   nombraba XCTest. Ahora indica `POST /session/SESSION_ID/bridge`.

## Tokens: una pantalla real

Se contó con `cl100k_base` el cuerpo HTTP **exacto** de observe guardado en
`avd/05-receipt-observe.json`, y el XML completo, sin comprimir, obtenido con
`adb shell uiautomator dump` en el mismo comprobante después del replay de Maestro.
No se incluyen cabeceras HTTP, prompts ni consumo total del escenario/modelo.

| Lectura | Tokens |
|---|---:|
| Observe, respuesta JSON | 90 |
| Árbol completo, payload XML | 815 |
| XML / observe | **9,06×** |

El resultado queda dentro del objetivo orientativo 7×–12× del documento. Es una sola
pantalla de una app nativa pequeña; no demuestra la misma proporción en otras apps/OEM.
`measure_tokens.py` reproduce el cálculo y escribe `avd/tokens.json`.

## Repetir

Configura `ANDROID_HOME`, JDK 17, SDK platform 35/build-tools 35.0.0 y un AVD arm64 o
un físico online/autorizado. Desde la raíz del repositorio:

```sh
Scripts/build_android_runner.sh
swift build -c release
CUYSCOUT_AUTORECORD=true CUYSCOUT_ARTIFACT_DIR=/tmp/android-artifacts \
  CUYSCOUT_CONFIG=/tmp/android-smoke-no-config CUYSCOUT_BIND_ADDRESS=127.0.0.1 \
  .build/release/cuyscout 18765
# En otro terminal; --system-alerts requiere API 33+ y diálogo sin permiso concedido:
python3 Scripts/smoke_android_device.py --serial SERIAL \
  --artifacts /tmp/android-artifacts --output /tmp/android-smoke --system-alerts
```

El script instala/limpia **solo la app ficticia**, comprueba el flujo, guarda el
comprobante y exportaciones, verifica permisos si se pidió y ejecuta los tres replays.
`--preparations` sin valores omite replays para recapturar únicamente el flujo.
La carpeta `--output` debe ser nueva o estar vacía.
Al terminar la sesión se debe haber eliminado su archivo `/data/local/tmp/cuyscout-*.json`.

Para Appium, instala UiAutomator2 y genera un proyecto Android con `cuyscout init`.
Copia el artefacto y TypeScript a `output/smoke.cuyscout.json` y `output/smoke.ts`, y
`replay-values.json` a `fixtures/replay-values/smoke.json`. Ejecuta
`CUYSCOUT_APPIUM_UDID=SERIAL scripts/replay-appium.sh smoke` desde ese proyecto.
Para Maestro:

```sh
maestro --device SERIAL test /tmp/android-smoke/maestro.yaml \
  -e PASO_1_TEXT=demo -e PASO_6_TEXT=12.50 \
  -e 'PASO_11_EXPECTED=Pago completado · Operación DEMO-0001 · S/ 12.50'
```

## Regresiones y empaquetado

`checks.json` registra 479 tests Swift y 30 tests JVM en verde, la prueba HTTP/MCP con
dobles, los APK y Lint, la compilación release y `cuyscout-app`, y la generación del DMG.
El DMG local está firmado, sin notarizar por falta de perfil; no se publicó.
CI compila también la app ficticia sin necesitar un emulador.

Quedan pendientes el humo físico completo, el reverse USB, las variantes OEM y apps
Compose/WebView. La evidencia AVD no sustituye esas comprobaciones.
