# Revisión del PR #50 — 15 de octubre de 2026

Se revisó el diff contra `codex/android-step-7-agent-project`, incluidos runner,
exportador, app de prueba, script, CI y evidencia. Se corrigieron cuatro problemas:

1. **Selector por placeholder incompatible con Appium.** El backend nativo ofrece el hint
   como etiqueta de un campo sin contentDescription, pero el exportador solo buscaba
   content-desc o texto no editable. Ahora busca `hint` con la misma prioridad que el
   runner y distingue el placeholder del valor escrito mediante `showing-hint`.
2. **Aserciones incorrectas con una etiqueta literal `null`.** La heurística que descartaba
   la cadena `"null"` también descartaba descripciones válidas y podía aceptar un texto
   distinto al que verifica el runner. La aserción usa los atributos XML del elemento
   seleccionado, conserva la prioridad descripción/texto/estado y no confunde un hint
   con el valor de un campo vacío. UiAutomator2 ejecuta XPath relativo sobre un documento
   con el elemento como raíz; se comprueba también el ID del resultado para impedir que
   una coincidencia de un descendiente haga pasar la aserción del padre.
3. **Evidencia mezclada al repetir `--output`.** Se añadían eventos al log anterior y
   podían quedar resultados de replay de otra corrida. El script exige una carpeta nueva
   o vacía antes de contactar al gateway. Hay pruebas que verifican que los archivos
   anteriores permanecen intactos y que no aparece un fallo de conexión en su lugar.
4. **Hints visibles de TextView borrados.** El filtro `isShowingHintText()` se aplicaba a
   todos los nodos, aunque el hint de un TextView no editable es su texto visible. Se
   restringió el filtro a campos editables. Una prueba nueva usa AccessibilityNodeInfo
   reales en el AVD y comprueba el texto no editable, el valor vacío de un EditText y la
   escritura por su hint sin añadir el placeholder.

## Validación

- Las nuevas regresiones del exportador y de la carpeta de evidencia fallaron antes de
  las correcciones. El TypeScript exacto generado se compila y ejecuta con WebdriverIO
  contra el doble W3C para iOS/Android y preserve/restart/reinstall.
- Casos Android: comprobante sin descripción, descripción literal `null` distinta al
  texto, descripción con ambas clases de comillas, búsqueda y escritura por hint,
  aserciones del campo vacío y con texto. Casos negativos: texto distinto a la descripción
  y texto de un hijo que no debe validar a su padre; ambos deben fallar y cerrar sesión.
- **Appium real en el mismo AVD AOSP arm64/API 35:** se ejecutó el flujo completo mediante
  `replay-appium.sh`, incluyendo una aserción inicial del campo vacío y escritura usando
  la etiqueta `Usuario de prueba`, y la aserción final del comprobante. Resultado: pasa.
  `review/hint-replay-input.cuyscout.json` es una variante **derivada** del artefacto
  original para esta regresión, no una nueva grabación. `review/hint-replay.ts` es su
  exportación exacta; `review/appium-replay.log` conserva la ejecución.
- La prueba `AndroidUiBackendTest` falló con el código anterior y pasó tras la corrección
  en el AVD real. Sus salidas están en `review/hints-before.log` y `review/hints-after.log`.
- 479 tests Swift, 30 JVM, 1 de instrumentación real y 2 pruebas Python del script; APKs/Lint, release, app macOS,
  DMG y regresiones HTTP/MCP/proyectos. Los resultados finales están en `review/checks.json`.

La prueba física/OEM sigue pendiente por falta de dispositivo. No se repitió la medición
de tokens: la evidencia original del comprobante conserva su alcance y sus valores.

## Repetir la regresión real

Con un proyecto Android de la app ficticia y Appium/UiAutomator2 configurados, copia
`review/hint-replay-input.cuyscout.json` a `output/review.cuyscout.json` y regenera el
TypeScript con la CLI actual:

```sh
cuyscout export-appium output/review.cuyscout.json ts output/review.ts
CUYSCOUT_APPIUM_UDID=SERIAL scripts/replay-appium.sh review
```

La variante contiene exclusivamente los valores ficticios públicos de esta app, por lo
que no requiere un archivo de sustitución de valores. Para las regresiones sin Android:

```sh
swift test --parallel
python3 -m unittest discover -s Tests/Conformance -p test_android_smoke_script.py
```

Para la regresión de hints en el AVD, compila/instala los APK del host y de tests y ejecuta:

```sh
adb -s SERIAL shell am instrument -w \
  -e class com.cuycoders.cuyscout.runner.AndroidUiBackendTest \
  com.cuycoders.cuyscout.host.test/androidx.test.runner.AndroidJUnitRunner
```
