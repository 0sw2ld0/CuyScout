---
name: cuyscout-android
description: Automatiza una app Android con CuyScout desde un APK y su applicationId o una app instalada, en AVD o físico, sin acceso al código fuente. Usa el gateway y el bucle observe → decidir → execute para grabar y exportar pruebas.
---

# Conducir una app Android con CuyScout

CuyScout controla el dispositivo. Consulta `/sessions` o `cuyscout_list_sessions` antes de
crear una sesión; conserva y reutiliza la de este proyecto. No repitas una creación de
resultado incierto ni cierres sesiones ajenas. Lee el perfil privado mediante
`scripts/cuyscout-connection.sh`; nunca inventes o escribas el token en el proyecto.

## Preparar el proyecto

```bash
cuyscout init /ruta/pruebas --platform android --app-path /ruta/App.apk \
  --application-id com.example.app --app-activity .MainActivity --driver-id android-emulator
# App ya instalada: omite --app-path; usa --driver-id android-device para un físico.
SESSION=$(scripts/open-session.sh)
```

`.cuyscout-project.json` contiene `android.apk`, `applicationId`, `activity` opcional,
`driverId`, `deviceId` y `avd` opcionales. Los scripts eligen plataforma y destino con esos
datos; `CUYSCOUT_DRIVER_ID`, `CUYSCOUT_DEVICE_ID` y `CUYSCOUT_APP_ACTIVITY` permiten elegir
otro destino. Las rutas de APK son locales al host del gateway, no al cliente MCP.

También puedes abrir la sesión con `cuyscout_create_session`: usa `platformName: Android`,
`bundleIdentifier` como package, `appPath` solo para instalar y `appActivity` opcional.
Los drivers son `android-emulator` y `android-device`. En HTTP usa `appium:appPackage`,
`appium:appActivity`, `appium:avd` y `appium:udid`. El gateway instala y arranca el runner.
MCP en modo local requiere integrar el puente manualmente; prefiere modo gateway.

## Observar, decidir y ejecutar

La lectura habitual y la primera de cada vuelta es `observe`, con unas 15–20 acciones:

```
observe → decidir → execute → observe
```

`actions` ofrece controles con selectores listos para usar; `texts` ofrece textos para
verificar resultados. Ejecuta solo `actions[i].action`, con el valor de entrada resuelto,
nunca la sugerencia completa. MCP ofrece `cuyscout_observe` y `cuyscout_execute`; HTTP usa
`GET /session/{id}/observe?maxActions=20` y `POST /session/{id}/actions` con el objeto action.
No inventes selectores, coordenadas ni capturas: usa árbol/captura solo para diagnóstico.
`accessibilityIdentifier` corresponde a resource-id (sin package) o Compose testTag expuesto;
`label` a contentDescription o texto no editable; `value` al contenido editable/estado.
`predicate` de iOS no se admite. Los roles son button/textfield/statictext/switch… y las
coordenadas del gateway son dp. Espera `interactionReady`; `runner_starting` señala arranque,
`bridgeConnected` conserva el significado de registro, no garantiza aún interacción.

## Conexión y errores

El host necesita adb; para AVD también emulator y su imagen. Los APK del runner se compilan
con `Scripts/build_android_runner.sh` (JDK 17/SDK 35) o se suministran por configuración.
El emulador usa 10.0.2.2, USB usa adb reverse y Wi-Fi exige bind/URL alcanzables y token.
Un físico debe estar conectado, desbloqueado y autorizado (`adb devices -l`). No requiere
Xcode, firma Apple ni modo iPhone. Consulta doctor y readiness antes de cambiar el entorno.
Si una acción falla o su resultado es incierto, observa antes de decidir. No repitas pagos,
transferencias ni otras operaciones irreversibles sin verificar el estado real.

## Grabación, replay y exportación

La sesión graba automáticamente. Al terminar, exporta artefacto y TypeScript/Maestro antes
de cerrar la sesión; `scripts/close-session.sh` conserva evidencia. No afirmes éxito sin
verificar las assertions y el resultado del negocio. Guarda valores sensibles como
parámetros de ejecución; nunca tokens o datos personales en reglas o logs.

`replay-cuyscout.sh` usa el gateway; `replay-appium.sh` usa Appium UiAutomator2 y el TypeScript
exportado. Ambos aceptan `CUYSCOUT_REPLAY_PREPARATION=preserve|restart|reinstall`: preservar,
reiniciar conservando datos o borrar datos. Para Appium deja el físico online o el AVD
encendido y comprueba requisitos con `scripts/replay-appium.sh --check`. La actividad debe
estar grabada/configurada o debes proporcionar un APK para que Appium la resuelva.
`ANDROID_APP_ACTIVITY`, `ANDROID_APP_PACKAGE` y `CUYSCOUT_APPIUM_UDID` permiten cambiar esos
datos. La exportación TypeScript convierte dp a píxeles para Appium automáticamente.
