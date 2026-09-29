# Auditoría de Luna

Tarea 01a0c9b6-9378-7252-b399-05b4241fc8af, completada en 117142 ms.
GET /agent-help: 200. Primer POST /session: 200 tras 13556 ms; devolvió
value.sessionId = 5D470F76-FFF7-4C31-87D0-BB2C02A8E9C5.
Segundo POST idéntico: 400, «No se encontró un simulador disponible».

El informe del agente afirma incorrectamente que no hubo sesión válida. No consumió
la sesión creada, no pidió readiness/observe, no pagó y no exportó TypeScript.
La tarea terminó por decisión del agente, sin alcanzar límites externos.
El registro de la tarea muestra la salida completa del primer POST; no se presupone
qué parte recibió/interpretó el modelo cuando el comando tardó más que el primer yield.

El coordinador cerró la sesión huérfana con DELETE directo al puerto 4725, respuesta
200 {value:null}, fuera de las tres llamadas exploratorias medidas. Después apagó
el simulador. No se alteró el informe original ni se inyectaron pistas al agente.
Clasificación: fallo de manejo de sesión/respuesta en esta corrida; no se demuestra
un defecto nuevo del servidor ni se sustituye esta corrida por un éxito posterior.
