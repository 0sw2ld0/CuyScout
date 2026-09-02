---
name: cuyscout-ios
description: Automatiza una app iOS con CuyScout teniendo solo su instalador (.app o .ipa) y un objetivo en lenguaje natural — probar un flujo, ejecutar un escenario Gherkin, explorar una pantalla o generar una prueba reproducible, sin acceso al código fuente de la app. Úsala siempre que se conduzca una app iOS a través de CuyScout.
---

# Conducir una app iOS con CuyScout

CuyScout es el único que toca el dispositivo. Tú observas, decides y ejecutas. Nunca adivines
coordenadas ni deduzcas la estructura de la app: cada observación ya te entrega selectores
semánticos estables.

## El bucle

```
observe  →  decidir  →  ejecutar  →  observe
```

`observe` es la lectura de pantalla normal y es lo primero que haces en cada vuelta.
Te devuelve las dos cosas que necesitas:

- **`actions`** — los controles accionables, con su selector y si se escriben o se tocan.
  Es lo que usas para **actuar**.
- **`texts`** — los textos visibles con su identificador. Es lo que usas para **verificar**:
  importes, códigos de operación, mensajes de error, saldos.

```bash
curl "$CUYSCOUT/session/$SESSION/observe?maxActions=15"
```

Cuesta del orden de 300 tokens. Llámala tantas veces como haga falta.

## Abrir la sesión

Solo necesitas la ruta del instalador. CuyScout resuelve el `.ipa` a su `Payload/*.app`, lee
el bundle id del `Info.plist`, instala y lanza su runner.

```bash
curl -X POST $CUYSCOUT/session -H 'Content-Type: application/json' -d '{
  "capabilities": { "alwaysMatch": {
    "appium:app": "/ruta/a/App.ipa",
    "appium:automationName": "XCUITest"
  }}}'

curl -X POST $CUYSCOUT/session/$SESSION/timeouts \
  -H 'Content-Type: application/json' -d '{"implicit":8000}'
```

El runner tarda unos segundos. **Espera en `readiness`, no reintentando acciones:**

```bash
curl "$CUYSCOUT/session/$SESSION/readiness"
```

Mientras reporte el bloqueo `xctest_runner_starting` no hay nadie atendiendo; una acción
enviada ahora falla al instante con ese mismo motivo. No reinstales ni recrees la sesión.

## Ejecutar acciones

```bash
curl -X POST $CUYSCOUT/session/$SESSION/actions -H 'Content-Type: application/json' \
  -d '{"type":"tapElement","selector":{"strategy":"accessibilityIdentifier","value":"btn_login"}}'

curl -X POST $CUYSCOUT/session/$SESSION/actions -H 'Content-Type: application/json' \
  -d '{"type":"typeElement","selector":{"strategy":"accessibilityIdentifier","value":"input_email"},"text":"demo@ejemplo.com"}'
```

`typeElement` se ocupa del foco de teclado por su cuenta: toca el campo, espera el teclado y
escribe. No lo orquestes tú.

Usa siempre el selector que te dio `observe`. Si un control no tiene identificador, `observe`
te habrá dado su `label`; úsalo. Las coordenadas (`tap` con x/y) son el último recurso y
producen pruebas que se rompen: no las uses si hay un selector semántico.

## Verificar antes de una acción irreversible

Antes de confirmar un pago, aceptar una transferencia o borrar algo, contrasta lo que la app
afirma con tu objetivo. `texts` ya te lo da:

```
label_service_result_operation: N° Operación: SP860351
label_service_result_amount:    Monto pagado: S/ 120.00
label_service_result_account:   Desde: Cuenta Corriente ****1234
```

Si algo no coincide con el objetivo, cancela y repórtalo. No confirmes "a ver qué pasa".

## No descargues el árbol de accesibilidad completo

`accessibilityTreeWithOptions` cuesta entre **7 y 12 veces** lo que `observe` y es casi todo
geometría y contenedores anónimos que no puedes accionar. `observe` ya trae los controles y
los textos.

Pídelo solo si `observe` no trajo algo que necesitas y puedes decir qué es. Si te sorprendes
pidiéndolo en cada vuelta, el problema es que no estás leyendo el campo `texts`.

Lo mismo con los screenshots: una captura cuesta decenas de miles de tokens. No los pidas
salvo que la persona pida explícitamente evidencia visual.

## Cuando algo no avanza

`observe` devuelve `stateId` y `changed`. Si `changed` es `false` después de un tap, la acción
no tuvo efecto: **elige otra, no la repitas**. Tres acciones iguales sin cambio de pantalla y
`agent-state` te marcará `loopDetected` con el aviso
`stop_repeating_ineffective_action_and_choose_another`.

Para una decisión con más contexto —métricas, últimos errores, bloqueos y lecciones
aprendidas de sesiones anteriores sobre esta misma app— usa `agent-state`:

```bash
curl "$CUYSCOUT/session/$SESSION/agent-state?maxActions=10"
```

Ante un fallo, el error de CuyScout dice qué pasó. `no such element` significa que el selector
ya no resuelve: vuelve a observar antes de reintentar, o usa `?repair=true` en la acción para
que intente una alternativa semántica.

## Dejar una prueba reproducible

Si el objetivo era generar una prueba, graba desde el principio y exporta al final:

```bash
curl -X POST $CUYSCOUT/session/$SESSION/recording/start
# ... el flujo ...
curl "$CUYSCOUT/session/$SESSION/recording/plan/validate"
curl "$CUYSCOUT/session/$SESSION/recording/appium/typescript"
```

`validate` avisa de coordenadas, selectores frágiles y datos sensibles antes de exportar.

## Al terminar

```bash
curl -X DELETE $CUYSCOUT/session/$SESSION
```

Si aprendiste algo reutilizable sobre esta app —un control que tapa el teclado, una pantalla
que tarda— guárdalo para las próximas sesiones:

```bash
curl -X POST $CUYSCOUT/lessons -H 'Content-Type: application/json' -d '{
  "scope":"project","sessionId":"'$SESSION'",
  "title":"...","observation":"...","recommendation":"...","tags":["..."]}'
```

Nunca guardes credenciales ni datos personales como lección.

## Referencia

Detalle completo del contrato y de los endpoints en `AGENT-GUIDE.md` en la raíz del repo.
