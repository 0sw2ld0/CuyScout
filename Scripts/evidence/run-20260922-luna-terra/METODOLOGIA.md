# Sedapal: Luna y Terra, 22 de septiembre de 2026

## Alcance

Cuatro celdas independientes: `gpt-5.6-luna` y `gpt-5.6-terra`, ambas con razonamiento `medium`, usando CuyScout HTTP o Appium 3.2.2 / XCUITest. Cada tarea conoce la aplicación únicamente por las respuestas de su herramienta. No tiene acceso al código, `AGENT-GUIDE.md`, pruebas anteriores ni capturas. Los prompts completos están en este directorio.

El usuario autorizó explícitamente pagos simulados y reproducciones en CuyWallet DEMO local, sin dinero real. Esta autorización no elimina restricciones del entorno: si una herramienta rechaza un pago, la corrida se registra como bloqueada; no se sortea el rechazo por otra ruta.

Escenario: iniciar sesión DEMO, elegir Sedapal, suministro 19891201, monto elegido por el agente; verificar resumen antes del pago y comprobante/número de operación después. Entregable: TypeScript standalone con `tsx`, `webdriverio`, `node:assert`, parámetros de entorno, selectores observados y esperas. Solo un pago por corrida, sin reintento automático ante incertidumbre.

## Comparación con Sonnet

Se conserva el escenario y la medición HTTP de la segunda prueba histórica, no se mezcla con los experimentos MCP previos de Luna. El proxy cuenta la línea de petición y cuerpo de entrada más el cuerpo de respuesta con `cl100k_base`, igual que el medidor histórico. No cuenta cabeceras, razonamiento, escritura del script ni tokens reales del contexto del modelo; no es una medición de dinero gastado.

Hay diferencias deliberadas respecto de Sonnet: CuyScout aprende de `GET /agent-help` en vez de una guía del repositorio, hay límites externos y la comprobación del número de operación queda explícitamente después del pago. Se usa una versión de CuyScout reparada, no el binario histórico. Por ello es una nueva evaluación, no una réplica experimental idéntica. Los límites no deben interpretarse como una estimación de cuánto habría tardado un agente sin ellos.

Los resultados incompletos NO se convierten en una ventaja de tokens frente a un escenario completado. Una llamada que retorna HTTP 200 tampoco demuestra por sí sola que el agente aprovechó la respuesta o que el escenario terminó.

## Aislamiento y control

Cada celda empieza en un simulador recién creado. Appium recibe la misma aplicación ya instalada y WebDriverAgent precalentado mediante crear/cerrar sesión sin navegar; esa preparación no entra en el medidor. CuyScout recibe el instalador IPA y crea su sesión. Los servidores CuyScout usan directorios de artefactos y lecciones separados.

`Scripts/benchmark_guard.py` impone un máximo de 80 llamadas de trabajo, 480 segundos desde la primera petición y hasta 90 segundos para una petición en curso. Permite `DELETE /session/...` después del corte para limpiar. Bloquea el cuarto envío de la misma acción de escritura aunque se intercalen lecturas, tres errores repetidos y seis observaciones de pantalla sin cambios. Las búsquedas W3C de elementos no se tratan como escrituras. Ante HTTP 500 o superior en CuyScout corta inmediatamente. Un error de transporte también corta por resultado potencialmente incierto.

Los eventos de control y las peticiones rechazadas por el límite se guardan en `.control.jsonl`, fuera del tráfico al servidor. Un archivo `.stop` permite al coordinador cortar una corrida. Los registros `.jsonl` se crean exclusivamente: no se permite mezclar una repetición en el mismo archivo.

El límite del proxy controla el tráfico, no el tiempo que el modelo dedica posteriormente a redactar su informe. El coordinador observa las tareas y sus resultados. Un evento tardío `time_limit` cuando una tarea ya cerró sesión no significa que esa tarea agotase el límite durante el escenario.

## Reparación y repeticiones

Base inicial: `e2c1b30`. Reparación y control: `043f12d`.

Segunda reparación `51c3bb6`: el helper exportado devolvía un `ChainablePromiseElement` con una anotación `Promise<WebdriverIO.Element>`. La incompatibilidad se confirmó también en el helper original, no solo en la adaptación del agente. Ahora se devuelve `element.getElement()`, con comprobación TypeScript y regresión Swift. Tras descubrirlo se detuvo la publicación definitiva y se lanzaron nuevas corridas CuyScout, conservando las anteriores como diagnóstico. El usuario renovó la autorización después de conocer los rechazos de seguridad; se repite también Luna/Appium, sin cambiar su consigna de exploración.

- Luna/CuyScout, intento 1: la ayuda HTTP mostraba argumentos de MCP y el agente envió un envoltorio `action`. El servidor lo convirtió en HTTP 500 genérico. Se detuvo inmediatamente, se cerró la sesión y se invalidó el intento. La ayuda ahora distingue HTTP, muestra el cuerpo crudo y los errores de decodificación devuelven HTTP 400 con una indicación útil y sin ejecutar acción.
- Luna/CuyScout, intento 2: nueva tarea y simulador, misma consigna salvo UDID, con el código reparado. El POST de sesión devolvió 200 y un `value.sessionId`; Luna volvió a crear sesión, obtuvo un 400 por dispositivo ocupado y afirmó erróneamente no haber recibido sesión. Se conserva como fallo del agente, no se descarta para mejorar el resultado. El coordinador cerró la sesión huérfana directamente, fuera de la medición.
- Terra/CuyScout, intento 1: error del coordinador al arrancar el servidor en un puerto diferente. Solo hubo GET de ayuda con 502; no se creó sesión ni se tocó la app. Se conserva como preparación inválida, se corrigió el puerto y se comprobó directamente antes de lanzar una tarea nueva. El simulador siguió virgen.

Cada defecto confirmado de CuyScout requiere detener, reparar y volver a empezar en otra tarea limpia. Un fallo de razonamiento o una restricción del entorno se reporta como tal: no se reclasifica automáticamente como defecto de CuyScout ni se oculta repitiendo hasta obtener éxito.

## Verificación del entregable

Se conservan los archivos originales y sus SHA-256. Compilar, pagar durante la exploración y reproducir el archivo en una instalación limpia son resultados distintos. Una prueba parcial que se detiene explícitamente antes del comprobante no se declara reproducible. No se ejecuta un pago desde el coordinador para eludir un rechazo de seguridad recibido por un agente.

Recalcular métricas: `python3 Scripts/evidence/run-20260922-luna-terra/summarize.py`. La duración HTTP es la suma de latencias; el intervalo de tráfico y la duración completa de la tarea son métricas diferentes. Las reproducciones, si proceden, se registran separadas y no se suman al coste exploratorio.
