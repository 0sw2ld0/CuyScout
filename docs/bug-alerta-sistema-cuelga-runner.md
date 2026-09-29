# Bug: tocar la app mientras aparece una alerta del sistema cuelga el runner XCTest

## Síntoma

Tras iniciar sesión en una app, iOS muestra de forma asíncrona la alerta del sistema
«¿Guardar contraseña?» (*Ahora no* / *Guardar*), que pertenece a SpringBoard, no a la app.
Si el agente envía un `tapElement` sobre un elemento de la app justo cuando la alerta está
apareciendo, el comando no falla rápido: agota el timeout del bridge y **el runner queda
inutilizable** para el resto de la sesión (todo `observe` y toda acción siguiente devuelven
`Timeout esperando respuesta de XCTest`).

En el benchmark `Scripts/evidence/run-20260926-laya-benchmark/` esto arruinó 3 de 5 corridas
(de 200 a 415 s perdidos cada una) al azar, sin importar el decisor.

## Reproducción (verificada el 2026-09-26, CuyWallet, simulador iPhone 17 Pro iOS 26.5)

```bash
# sesión nueva con el .app, luego:
POST /session/$S/actions {"type":"typeElement","selector":{"strategy":"accessibilityIdentifier","value":"input_email"},"text":"..."}
POST /session/$S/actions {"type":"typeElement","selector":{"strategy":"accessibilityIdentifier","value":"input_password"},"text":"..."}
POST /session/$S/actions {"type":"tapElement","selector":{"strategy":"accessibilityIdentifier","value":"btn_login"}}
GET  /session/$S/observe   # -> pantalla de inicio (acciones de la app)
sleep 1
GET  /session/$S/observe   # -> vacío: la alerta está apareciendo
POST /session/$S/actions {"type":"tapElement","selector":{"strategy":"accessibilityIdentifier","value":"btn_quick_transfer"}}
# -> 30 s y luego {"error":"unknown error","message":"Timeout esperando respuesta de XCTest"}
GET  /session/$S/observe   # -> el mismo timeout; la sesión ya no se recupera
```

Si se espera un poco más, `observe` sí muestra la alerta (acciones `Ahora no` y `Guardar`
con `strategy: label`) y tocar `Ahora no` funciona. El problema es la ventana de transición y
la falta de recuperación.

## Dónde está en el código

- `Runner/ScoutRunner/ScoutRunner/ScoutBridgeRunner.swift:250` — `resolve(_:)` ya busca botones
  de alertas de SpringBoard, pero **solo** cuando el selector es `label`. Un tap por
  `accessibilityIdentifier` sobre la app no comprueba si hay una alerta del sistema encima.
- `Sources/CuyScoutCore/ScoutEngine.swift:1896` — `execute(_:)` espera 30 s el resultado del
  runner; al agotarse lanza `Timeout esperando respuesta de XCTest`, pero no marca el runner
  como colgado ni intenta recuperarlo, así que cada comando posterior vuelve a esperar 30 s.
- `observe` devuelve `texts` y `actions` vacíos durante la transición, sin indicar que la
  pantalla está cambiando.

## Cambios propuestos

1. **Runner — fallar rápido ante una alerta del sistema:** antes de ejecutar una acción sobre
   la app, comprobar `XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists`.
   Si existe, no tocar: devolver de inmediato un error accionable, por ejemplo
   `system_alert_present` con el título y los botones de la alerta, para que el agente elija
   (`Ahora no`) en vez de colgarse.
2. **Observe — señalar la transición:** si la lectura sale vacía, o hay una alerta de
   SpringBoard apareciendo, indicarlo (por ejemplo `"settling": true` o un bloqueo en
   `readiness`) en vez de devolver una pantalla vacía sin explicación.
3. **Engine — detectar y recuperar un runner colgado:** tras un timeout del bridge, marcar el
   runner como no responsivo (bloqueo `xctest_runner_unresponsive` en `readiness`) y relanzarlo
   con la misma lógica de `launchRunner(sessionID:)` que usa el replay en frío, en vez de dejar
   que cada comando siguiente espere otros 30 s.
4. **Test:** en `Tests/CuyScoutCoreTests/`, cubrir al menos el punto 3 (un timeout del bridge
   deja `readiness` con el bloqueo y no encola más comandos a un runner colgado). El punto 1
   requiere el runner real; documentar la verificación manual con la reproducción de arriba.

## Mitigación temporal (ya aplicada en el benchmark)

`bench_laya.py` espera a que la pantalla se estabilice (dos `observe` no vacíos seguidos con
el mismo `stateId`) antes de decidir. Así el agente ve la alerta y la descarta. Es una
mitigación del lado del agente; el arreglo correcto es en CuyScout (puntos 1–3).
