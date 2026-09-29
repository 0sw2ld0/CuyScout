# Benchmark: generar la prueba con LLM solo vs. LLM + Laya (2026-09-26)

## Resultado final (modo `laya2`: estado de la petición + opciones acotadas + postcondiciones)

Verificación estricta sobre la pantalla final: «Transferencia exitosa», «Operación: OP…»,
«S/ 100.00» **y origen «Wallet Digital CUY»** (lo que pide el `.feature`: «origen cuywaller»).
Todas las corridas sin cuelgue del runner (estabilización de pantalla + manejo de alertas).

| Serie | Modo | Corridas | Correctas (estricto) | Falsos éxitos | Escenario (s)* | Decisión (s)* | Llamadas LLM* | Tokens LLM* |
|---|---|---|---|---|---|---|---|---|
| v2 | solo LLM | 5 | **0** | **5** | 73.0 | 44.8 | 9 | 13 721 |
| v2 | LLM + Laya | 5 | 4 | 0 | 81.1 | 31.2 | 2.2 | 4 489 |
| v3 | LLM + Laya | 5 | 3 | 0 | 69.6 | 21.4 | 3 | 6 165 |
| v4 | LLM + Laya | 5 | 3 | 0 | 67.3 | 19.5 | 2.3 | 4 807 |

\* Promedio sobre corridas correctas; para «solo LLM» sobre todas (ninguna fue correcta).

- **Fidelidad:** el modo solo LLM completó la transferencia 5/5 pero **siempre desde la cuenta
  por defecto**, ignorando el origen pedido, y aun así declaró éxito (5 falsos éxitos). El modo con
  estado respeta el origen y nunca declaró un éxito falso: cuando falla, lo dice.
- **Tokens / llamadas:** −65 % de tokens y ~4× menos llamadas al LLM (2–3 vs 9).
- **Tiempo:** decisión −55 % (≈20 s vs 45 s) y escenario −8 % (67 s vs 73 s) en v4, pese a hacer más
  acciones (12 vs 8), porque sí abre los selectores para elegir el origen correcto.
- **Latencia de Laya:** ~1 s en total por corrida (10–11 decisiones sin LLM: Laya, coincidencia
  determinista, opción única o descarte de interrupción).
- **Fallos restantes (≈40 %):** vienen del plan que genera el LLM (varía entre corridas: omitir el
  login, postcondiciones con texto literal distinto al de la app, pasos sin postcondición) o de
  falsos negativos al verificar un paso. No son errores de decisión de Laya.

### Con la regla de valores explícitos (serie `regla`, `--regla-valores`)

Se agregó al contrato del agente (AGENT-GUIDE.md, skill `cuyscout-ios`, `AGENTS.md` de
`cuyscout init` y `AgentContract.swift`): *cada valor que el escenario nombra se elige
explícitamente y se comprueba en el resumen; un valor preseleccionado no cuenta como elegido*.

| Serie | Modo | Corridas | Correctas (estricto) | Falsos éxitos | Escenario (s) | Decisión (s) | Llamadas LLM | Tokens LLM |
|---|---|---|---|---|---|---|---|---|
| regla | solo LLM + regla | 5 | **5** | 0 | 99.4 | 62.7 | 13 | 22 854 |
| v4 | LLM + Laya | 5 | 3 | 0 | 67.3 | 19.5 | 2.3 | 4 807 |

Con los dos modos haciendo el trabajo completo (abrir selectores y elegir el origen pedido), la
comparación queda pareja: **LLM + Laya usa −79 % de tokens, −82 % de llamadas y −32 % de tiempo**,
pero hoy es menos fiable (3/5 frente a 5/5) por la variabilidad del plan. La regla corrige el
modo solo LLM a costa de ~67 % más tokens que sin ella.

### Aprendizaje entre intentos (`learn_loop.sh`, `results/learn*`)

Cada prueba parte con memoria vacía (`CUYSCOUT_LESSONS_FILE` nuevo) y tiene hasta 3 intentos.
Un oráculo revisa los requisitos del escenario en la pantalla final. Si el intento falla (y no es
infraestructura), el LLM analiza el fallo —recibe *qué* requisito no se cumplió, no *cómo*
arreglarlo— y CuyScout guarda una lección candidata (confianza 0.5). El siguiente intento la lee de
CuyScout; al terminar se le informa el resultado con `POST /lessons/:id/feedback`.

**Ronda 1 (`learn-v1`, sin retroalimentación):** solo LLM aprendió «elegir explícitamente la cuenta
de origen» y acertó en el 2.º intento (3/3). LLM + Laya acertó en 1.er y 2.º intento en dos pruebas,
pero en la tercera el análisis culpó a *quick transfer* (el camino correcto) y cada intento reforzó
esa creencia falsa. Causa real: el arnés no daba por cumplido un «seleccionar» que navega. Esto
mostró que **CuyScout no podía bajar la confianza de una lección que no funciona**.

Cambios en CuyScout: `POST /lessons/:id/feedback` (`helped` +0.15 / `failed` −0.25 y `failures`),
lecciones bajo 0.3 descartadas (no se entregan ni reviven), `GET /lessons?includeDiscarded=true`
para auditar; 5 tests nuevos, suite completa 253/253.

**Ronda 2 (`learn`, con retroalimentación y arnés corregido):**

| Modo | Pruebas | Acertó en | Tokens hasta acertar (prom.) | Tiempo hasta acertar (prom.) | Lección |
|---|---|---|---|---|---|
| solo LLM (sin regla) | 3 | 2.º intento (3/3) | ~39 600 | ~163 s | «verificar/forzar la cuenta de origen» → `helped`, 0.5 → 0.65 |
| LLM + Laya | 3 | 1.er intento (3/3) | ~4 200 | ~66 s | no hizo falta |

En la ronda 2 ninguna lección falló, así que el descarte solo está cubierto por los tests unitarios.

### Qué hace `laya2` (ver `run_laya2_mode` en `bench_laya.py`)

1. El LLM planifica una vez: pasos con intención (`escribir`/`tocar`/`seleccionar`/`confirmar`/
   `verificar`), valor, variantes de la opción a elegir y postcondiciones tomadas del escenario.
2. Opciones acotadas por paso: solo el tipo de acción que corresponde, sin navegación global, sin
   controles ya usados ni reintentados.
3. Decisión en cascada: coincidencia determinista (tolerante a typos) → opción única → Laya
   (umbral 0.35; 0.6 si es irreversible) → LLM. Si el paso nombra qué elegir y no hay coincidencia
   clara, no se deja adivinar a Laya.
4. Un paso solo se cumple con **evidencia nueva** en pantalla (postcondición no vista antes); un paso
   irreversible sin postcondición toma la de la verificación siguiente.
5. Alertas del sistema (pocas acciones por label + texto que pregunta) se descartan sin avanzar pasos.

### Siguiente mejora sugerida

**Cachear el plan por `.feature`** (generarlo una vez, revisarlo y reutilizarlo): elimina la mayor
fuente de variabilidad y la llamada de planificación, dejando las corridas repetidas casi sin tokens.
Luego, cachear decisiones (pantalla, paso) → acción para no llamar a ningún modelo en re-generaciones.

---

## Primera iteración (modo `laya`, sin estado) — conservada como evidencia

Escenario: `CuyScoutTest/features/transferencia-propia.feature` (login + transferir S/ 100 entre
cuentas propias) sobre CuyWallet, simulador dedicado «Bench Laya 20260926» (iPhone 17 Pro,
iOS 26.5), gateway CuyScout local.

- **Modo `llm`:** Sonnet (`claude -p`, system prompt mínimo, sin herramientas) decide cada
  acción viendo escenario + historial + pantalla (`observe`).
- **Modo `laya`:** Sonnet descompone el `.feature` una vez en pasos atómicos; Laya
  (checkpoint `english`, 421M, local en MPS, umbral 0.35 calibrado con corridas previas) elige
  la acción de cada paso; si su confianza es baja se deriva a Sonnet. Las verificaciones buscan
  el texto esperado en pantalla, sin modelo.

Arnés: `bench_laya.py` (genérico: feature + fixtures + app + UDID). Serie: `run_series.sh`
(alternada, reinicia el simulador antes de cada corrida). Tabla: `summarize.py`.

## Resultados de la serie (`results/serie-*.json`)

| Corrida | Modo | Declaró éxito | Resultado real en pantalla | Escenario (s) | Decisión (s) | Llamadas LLM | Tokens LLM | Cuelgue XCTest |
|---|---|---|---|---|---|---|---|---|
| llm-1 | llm | sí | ✅ Transferencia exitosa, S/ 100.00 | 80.3 | 52.9 | 9 | 13 731 | no |
| llm-2 | llm | sí | ✅ Transferencia exitosa, S/ 100.00 | 65.9 | 39.2 | 9 | 13 733 | no |
| llm-3 | llm | no | — | 376.1 | 25.6 | 5 | 7 063 | **sí** |
| laya-1 | laya | no | — | 1002.5 | 35.3 | 6 | 8 340 | **sí** |
| laya-2 | laya | no | — | 996.6 | 28.7 | 5 | 6 956 | **sí** |
| laya-3 | laya | sí | ❌ quedó en «¿Confirmar transferencia?» (falso éxito) | 63.0 | 32.3 | 3 | 6 032 | no |

Promedio de corridas sin cuelgue:

| Modo | Corridas | Correctas | Escenario (s) | Decisión (s) | Llamadas LLM | Tokens LLM |
|---|---|---|---|---|---|---|
| llm | 2 | 2 | 73.1 | 46.0 | 9 | 13 732 |
| llm + Laya | 1 | 0 | 63.0 | 32.3 | 3 | 6 032 |

El costo en USD no se compara: varía por el caché de prompts del CLI entre corridas. Los tokens
sí son comparables.

## Conclusiones

1. **Ahorro real de tokens y llamadas:** con Laya bajan las llamadas al LLM de 9 a 3 y los
   tokens ~56 % (13.7k → 6.0k). Laya decide en decenas a cientos de ms en local y sin tokens.
2. **Ahorro de tiempo modesto:** −14 % de escenario (73 → 63 s), −30 % de tiempo de decisión.
   El tiempo del dispositivo (taps, teclado, estabilización) y la llamada de planificación
   pesan más que la decisión en sí.
3. **Pero hoy no es correcto:** Laya elige bien la acción cuando el paso es simple y el control
   es obvio (escribir correo/contraseña/monto, 0.7–0.96 de confianza), pero no sabe si un paso
   se cumplió. En la corrida 3 abrió una lista y dio por hecha la selección, eligió el destino
   dentro de la lista de origen, confundió *Continuar* con *Confirmar* y la verificación literal
   («S/ 100.00») pasó en la pantalla de confirmación. Resultado: **falso éxito**.
4. **Ruido dominante:** 3 de 6 corridas se perdieron por el cuelgue del runner con la alerta
   «¿Guardar contraseña?» (300–1000 s cada una), sin importar el decisor. Ver
   `docs/bug-alerta-sistema-cuelga-runner.md`. Mientras no se arregle, ningún benchmark es fiable.
5. **Ningún modo respetó «origen cuywaller»:** todas las corridas transfirieron desde Cuenta
   Corriente. Puede deberse al typo del `.feature` (¿«CuyWallet»/«Wallet Digital CUY»?).

## Siguiente iteración sugerida

- Arreglar el cuelgue en CuyScout (o desactivar la alerta en el simulador del benchmark) y
  repetir con ≥5 corridas por modo.
- Modo Laya v2 con **postcondiciones**: cada paso atómico del plan trae un efecto esperado
  verificable (por ejemplo «el resumen muestra Desde: …»), y el paso solo avanza si se cumple;
  si no, se deriva al LLM. Laya queda como elector de acción rápido, no como juez de progreso.
- Verificación final más estricta: exigir textos exclusivos del resultado (N° de operación),
  no solo el monto.

## Corridas de calibración (no cuentan en la tabla)

`results/llm-run0-bug-arnes`, `laya-run0-diseno-v1`, `laya-run0b-diseno-v2`,
`laya-run0c-xctest-timeout`, `cuelgue-serie-*`: iteraciones del arnés y del diseño del modo
Laya, conservadas como evidencia.
