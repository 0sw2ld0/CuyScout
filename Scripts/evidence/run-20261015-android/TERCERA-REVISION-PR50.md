# Tercera revisión del PR #50 — 15 de octubre de 2026

La revisión sobre `8e4b418` encontró una carrera en la protección del directorio de
salida. Dos ejecuciones podían comprobar simultáneamente que estaba vacío y escribir
sus sesiones en el mismo `http.jsonl`. La regresión reprodujo dos accesos al gateway
cuando solo uno debía estar permitido.

El script reserva ahora el directorio con creación exclusiva de `.smoke.lock` antes
de contactar con el gateway. Revalida su contenido tras obtener la reserva, porque
otra ejecución puede haber terminado entre ambas operaciones. Libera su propia reserva
en `finally`, incluso si falla el cierre de sesión. Una ejecución interrumpida de forma
abrupta puede dejar la reserva; en ese caso debe usarse otro directorio para conservar
la evidencia existente.

## Verificación

- **8 pruebas Python** pasan. Dos regresiones nuevas cubren ambas ejecuciones activas
  y una ejecución competidora que termina entre la comprobación inicial y la reserva.
  También se verifica que las salidas por error no dejen una reserva activa.
- **479 tests Swift** pasan, incluida la compilación y ejecución de los exports con
  WebdriverIO para ambas plataformas y los tres modos de preparación.
- Pasan las regresiones HTTP/MCP/proyectos para emulador y dispositivo con dobles.
- `Scripts/build_android_runner.sh` termina correctamente: APKs y Lint; los resultados
  de **31 tests JVM** siguen vigentes mediante las comprobaciones de Gradle UP-TO-DATE.
- `git diff --check` no encuentra problemas.

Estas pruebas no añaden evidencia de UI Android real ni repiten la medición de tokens.
Se conserva la evidencia AVD anterior; la prueba física sigue pendiente por falta de
un dispositivo. El empaquetado no cambia y no se repitió en esta revisión.

Para repetir las regresiones de concurrencia y verificación del script:

```sh
python3 -m unittest discover -s Tests/Conformance -p test_android_smoke_script.py
```
