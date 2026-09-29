# Repetición autónoma: Luna y Terra / CuyScout

22 de septiembre de 2026. Base d32d0da. Solo CuyScout, modelos medium, tareas y
simuladores nuevos, ejecución secuencial. Sin código, AGENT-GUIDE.md ni guía externa;
descubrimiento mediante /agent-help. Los prompts completos están archivados.

| Modelo | HTTP | Tokens de tráfico | Tiempo HTTP | Duración tarea | Resultado |
|---|---:|---:|---:|---:|---|
| Luna | 3 | 1 344 | 16,450 s | 117,142 s | Fallo de manejo de sesión; no inició el escenario |
| Terra | 24 | 8 744 | 32,145 s | 249,267 s | Tres assertions previas correctas; pago bloqueado por el entorno |

Ninguna corrida completó el escenario ni su replay. Estos costes parciales no son una
ventaja frente a Sonnet. Tokens cl100k_base del tráfico HTTP, no contexto total del
modelo ni facturación. Las duraciones de tarea incluyen razonamiento y archivos.

## Luna

El primer POST /session devolvió 200 y un sessionId. Luna hizo otro POST /session,
recibió 400 y reportó que no existía sesión válida. Su conclusión contradice el registro:
véase luna-audit.md. No se atribuye una causa interna del modelo sin evidencia. El
coordinador cerró la sesión huérfana (DELETE 200 fuera de la medición). No produjo TS.

## Terra

Registró assertText de Sedapal, suministro 19891201 y S/ 10.00 antes de pagar.
Reportó rechazo de la herramienta al intentar la confirmación financiera, pese a las
dos autorizaciones DEMO incluidas en el prompt. El pago no llegó al proxy HTTP y no
se reintentó por otra vía. No hay recibo ni operación. DELETE 200 incluido en las 24 llamadas.

La validación devolvió valid:false por exigir `describe(` en el exportador TypeScript
autónomo. Es un defecto confirmado de CuyScout, independiente del bloqueo del pago.
Se detuvo la evaluación: no se adapta el script para aparentar éxito.

## Reparación y comprobación posterior (no es otra corrida de modelos)

TestPlanValidator ahora exige la entrada autónoma y preflight en lugar de Mocha.
Los tests validan las siete exportaciones reales, rechazan una entrada TS eliminada
y conservan la advertencia de acciones observacionales: validez estructural no prueba
ejecución. Pasan 219 tests Swift, cero fallos.

El TS original de Terra compila sin cambios con tsc --noEmit (exit 0). Por tanto, la
conclusión original de Terra «no es un replay válido» se conserva como testimonio,
pero el rechazo estructural era un falso negativo. El archivo sigue siendo parcial:
compilarlo no comprueba pago/recibo ni equivale a reproducirlo.

SHA-256 del original: bd0a48c2366bb18115345400dbab4349d9b23ae752cf388f8a4dffcc0a93588f.
No se ejecutó ningún replay. Originales, parámetros y reportes se conservan por separado.

## Pendiente

### Endurecimiento posterior de creación de sesión

Ante un UDID ya reservado, CuyScout ahora responde `device_busy` y explica que una
creación anterior pudo haber tenido éxito: recuperar su respuesta, esperar la misma
invocación pendiente y no cerrar sesiones ajenas. La ayuda HTTP/MCP incorpora estas
instrucciones sin requerir AGENT-GUIDE.md. No reutiliza automáticamente sesiones de
otros clientes ni convierte un segundo POST en éxito ficticio. Un test comprueba que
el duplicado conserva la sesión original y que el dispositivo se puede reservar de
nuevo después de cerrarla. Suite actual: 221 tests, cero fallos.

Es una mejora del diagnóstico y contrato, no evidencia de que Luna haya superado una
nueva corrida. El bloqueo financiero de Terra sigue siendo externo. Se solicitó al
usuario acordar una repetición limitada al resumen, sin confirmación de pago.

Una nueva repetición limpia de ambos modelos después de esta corrección. No se lanza
automáticamente otra confirmación financiera para eludir el rechazo del entorno.
Debe resolverse ese bloqueo de autorización para repetir el escenario completo;
otra opción, con alcance acordado, es medir solo hasta el resumen sin pagar.
No se declara que Luna o Terra ya funcionen de extremo a extremo.
