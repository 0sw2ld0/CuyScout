# Feature: replay "en frío" de una sesión restaurada

## Implementado

`POST /artifacts/ID/replay` ejecuta restore + preparación del dispositivo/app + arranque y espera del runner + replay. Acepta `optimized`, `variables`, `resilient`, `deviceID` opcional para cambiar de dispositivo compatible, `preparation` (`preserve`, `restart`, `reinstall`) y `appPath`. `resetApp` sigue disponible como alias histórico. `POST /artifacts/ID/replay/preflight` devuelve comprobaciones de dispositivo, instalador, variables y runner sin ejecutar pasos. Cierra la sesión temporal al terminar o fallar y conserva el artefacto original. El endpoint `restore` mantiene su comportamiento anterior. Una grabación `ios-device` se reejecuta en iPhone físico; una `ios-simulator` permanece en simulador.

El runner usa la app instalada por `bundleIdentifier`; no requiere conservar el instalador original salvo para `reinstall` o para instalar en otro dispositivo. El `.app` macOS incluye el proyecto fuente del runner y lo compila en la Mac de destino cuando falta un prebuilt; se requiere Xcode. En iPhone físico se necesita también firma de desarrollo (`CUYSCOUT_DEVELOPMENT_TEAM`) y un gateway accesible desde el teléfono (`CUYSCOUT_DEVICE_GATEWAY_URL` y `CUYSCOUT_TOKEN`). `restart` reinicia el proceso sin borrar datos y `reinstall` limpia el contenedor de la app, pero deja intacto el llavero. El diseño y diagnóstico originales se conservan debajo como contexto.

Los proyectos creados o regenerados con `cuyscout init` ahora guardan, junto al `.ts`, un paquete completo `output/<escenario>.cuyscout.json`. Ese paquete incluye la sesión, dispositivo, driver, bundle ID y la grabación; los archivos `*.validate.json` y el JSON portable de pasos no son suficientes para importar una prueba por sí solos. Se puede importar en otro gateway con `POST /artifacts/import` y luego ejecutar con `POST /artifacts/ID/replay`.

Para uso normal, `scripts/replay-cuyscout.sh <escenario>` encapsula arranque del gateway, importación idempotente, preparación de la app y replay. Al cerrar la grabación, `close-session.sh` obtiene los valores originales desde `POST /session/ID/recording/replay-values` y los guarda en `fixtures/replay-values/<escenario>.json`, con permisos `600` y fuera de Git. El artefacto permanece redactado. El replay carga ese fixture automáticamente, igual que una prueba Appium carga sus datos de prueba. `CUYSCOUT_REPLAY_VALUES` permite sustituirlo en CI y acepta valores por ruta (`1.text`, `5.expected`, incluyendo rutas anidadas); los fallbacks globales `redacted`/`text` siguen disponibles.

## Problema

`POST /session/SESSION_ID/recording/replay` solo funciona mientras el runner XCTest
de esa sesión sigue vivo en el simulador. Si la sesión se borró (`DELETE /session/ID`)
y luego se restaura su artefacto persistido (`POST /artifacts/ID/restore`), el replay
falla con:

```json
{"success": false, "failedStep": 1, "error": "Registra primero el runner XCTest en /session/SESSION_ID/bridge/register", ...}
```

Esto se reprodujo así (repo `CuyCards/CuyScout`, gateway en `127.0.0.1:4723`):

```bash
curl -X POST http://127.0.0.1:4723/artifacts/$SESSION/restore
curl -X POST http://127.0.0.1:4723/session/$SESSION/recording/replay \
  -H 'Content-Type: application/json' -d '{"resetApp":true}'
# -> failedStep: 1, error: "Registra primero el runner XCTest en /session/SESSION_ID/bridge/register"
```

## Causa raíz (ya localizada)

- `Sources/CuyScout/HTTPServer.swift:165` — al crear una sesión normal (`POST /session`)
  con `appPath`, se llama `engine.launchRunner(sessionID:)` justo después de crear la
  sesión. Eso es lo que deja el runner XCTest arriba y listo para recibir comandos.
- `Sources/CuyScoutCore/ScoutEngine.swift:370` — `launchRunner(sessionID:)` internamente
  llama `registerBridge(sessionID:)` (línea 348) y arranca/adjunta el runner en el
  dispositivo.
- `Sources/CuyScoutCore/ScoutEngine.swift:125` — `restoreSessionArtifact(_:)` reconstruye
  el `Session` (dispositivo, eventos, grabación, checkpoints, navegación, etc.) pero
  **nunca llama `launchRunner`**. El dispositivo queda "leased" y el objeto `Session`
  existe, pero no hay proceso XCTest corriendo ni bridge registrado — de ahí el error
  al primer paso del replay.
- `Sources/CuyScoutCore/ScoutEngine.swift:1350` — es donde se lanza ese error exacto
  cuando no existe `bridges[sessionID]`.

## Cambio propuesto

Que `restoreSessionArtifact` (o el endpoint `POST /artifacts/ID/restore`) tenga la
opción de relanzar el runner automáticamente, dejando la sesión restaurada
inmediatamente interactiva — igual que una sesión creada de cero.

Opciones de diseño (a decidir en la implementación):

1. **Relanzar siempre** — `restoreSessionArtifact` llama `launchRunner(sessionID:)` al
   final, igual que hace `POST /session` en `HTTPServer.swift:165`. Más simple, pero
   cambia el comportamiento actual de `restore` (hoy es "barato": solo trae metadata).
2. **Flag opt-in** — `POST /artifacts/ID/restore?relaunchRunner=true` (o un campo en el
   body). Preserva el comportamiento actual por defecto y evita romper a quien ya
   depende de un `restore` liviano (por ejemplo, para solo inspeccionar metadata sin
   tocar el dispositivo).
3. **Endpoint nuevo** — algo como `POST /artifacts/ID/replay` que internamente hace
   restore + launchRunner + replay en un solo paso, sin tocar la semántica de
   `restore` existente. Es la opción que menos rompe compatibilidad hacia atrás.

Recomendación inicial: opción 3 (endpoint nuevo) o la 2 (flag opt-in) — evitar cambiar
el comportamiento por defecto de `restore`, que hoy varias partes del sistema (catálogo,
inspección) puede que asuman liviano.

## Qué falta validar

- Si el `Device` original (`artifact.session.device`) ya no existe o no está disponible
  (simulador borrado, distinto host), `restoreSessionArtifact` ya falla antes de llegar
  a esto (`ScoutError.invalidRequest("The artifact device is not available")`,
  `ScoutEngine.swift` ~línea 128) — ese caso no cambia con este feature.
- Si el `.app` original ya no existe en disco (se limpió el build), `launchRunner`
  necesita la ruta del instalador — confirmar de dónde la toma en el flujo normal de
  `POST /session` y si el artefacto restaurado la conserva (`artifact.session` no
  parece guardar `appPath`, solo `bundleIdentifier` — revisar `Session`/`SessionArtifactBundle`
  en `Sources/CuyScoutCore/Models.swift`).
- Añadir un test en `Tests/CuyScoutCoreTests/` que reproduzca el flujo completo: crear
  sesión → grabar pasos → cerrar sesión → restaurar artefacto → replay, y que pase sin
  el error de bridge.

## Motivación / contexto de negocio

Hoy, para reejecutar una prueba ya grabada y exportada (`.ts` en `output/` de un
proyecto como `CuyScoutTest`), el único camino soportado es Appium + WebdriverIO puro
(`npx tsx output/escenario.ts`), que requiere `npm install` de `webdriverio`/`tsx` por
fuera de CuyScout. Sería más simple para un agente poder reejecutar la misma prueba
usando solo el gateway de CuyScout (`curl`), sin ese segundo toolchain — especialmente
para una verificación rápida inmediatamente después de generar la prueba.

Esto **no reemplaza** el export a `.ts`: ese sigue siendo necesario para reproducir la
prueba sin que CuyScout esté corriendo en absoluto (CI externo, auditoría, entornos sin
Swift/Xcode). Este feature es un atajo adicional para cuando CuyScout sí está disponible.
