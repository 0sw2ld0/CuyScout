# Segunda revisión del PR #50 — 15 de octubre de 2026

La revisión sobre `9019114` encontró y corrigió tres fallos adicionales:

1. **Estado distinto en el replay Appium.** El backend Android normaliza el valor de
   los controles checkable con `selected || checked`. El exportador consultaba solo
   `checked`, por lo que podía buscar/tocar otro control o producir una aserción distinta
   a la nativa cuando `selected=true` y `checked=false`. Tanto los selectores por valor
   como las aserciones sin etiqueta/texto usan ahora la misma regla que el runner.
2. **Verificaciones eliminadas por Python optimizado.** `python -O` eliminaba los
   `assert` del script y permitía imprimir `PASS` tras observar la pantalla incorrecta,
   no encontrar los botones de permisos o recibir un replay fallido. Se reemplazaron
   por comprobaciones explícitas que lanzan errores en ambos modos.
3. **Replay vacío aceptado.** Un resultado `success=true, executedSteps=0` también se
   presentaba como un escenario completado. El humo exige ahora pasos ejecutados además
   de un resultado exitoso. El resultado fallido se conserva en el JSON de evidencia.

## Verificación

- Las regresiones del exportador y del script fallaron antes de las correcciones.
  `review-2/export-before.log`, `review-2/http-fixture-before.log` y
  `review-2/empty-replay-before.log` conservan las reproducciones.
- El TypeScript exacto generado se compila y ejecuta con WebdriverIO para iOS y Android
  con preserve/restart/reinstall. En Android se comprueban los estados selected-only,
  checked-only y ambos falsos, el primer control elegido para tocar y el rechazo de una
  aserción falsa sobre el control seleccionado. Continúan pasando los casos de hints,
  descripción literal `null`, comillas y aislamiento de descendientes de la revisión anterior.
- Un test JVM adicional fija el contrato nativo de selección por valor y assertText.
  Hay **31 tests JVM** y **479 Swift** en verde.
- Las **6 pruebas Python** incluyen los dos casos de protección de evidencia anteriores
  y cuatro verificaciones nuevas ejecutadas con y sin `-O`: pantalla incorrecta,
  permisos ausentes, replay fallido y replay vacío. Las sesiones se cierran también al
  fallar una comprobación.
- Pasan las regresiones HTTP/MCP/proyectos, APKs/Lint, release, `cuyscout-app` y DMG.
  El DMG local está firmado, sin notarizar; no se publicó. `review-2/checks.json` recoge
  los resultados.

Estas regresiones usan fixtures HTTP/W3C y JVM; no representan nuevas pruebas en Android
real. La evidencia AVD de las revisiones previas se conserva. El físico/OEM sigue pendiente
por falta de dispositivo. No se repitió la medición de tokens.

## Repetir

```sh
swift test --parallel
python3 -m unittest discover -s Tests/Conformance -p test_android_smoke_script.py
Scripts/build_android_runner.sh
python3 Scripts/test_android_sessions.py .build/release/cuyscout
```

Los tests HTTP del script usan un servidor local y, para permisos, un adb de prueba sin
efectos. Un `PASS: real Android` en los logs **anteriores** es precisamente el falso positivo
reproducido con ese fixture, no una ejecución real del escenario.
