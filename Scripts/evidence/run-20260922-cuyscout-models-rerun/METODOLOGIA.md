# Repetición Luna y Terra: solo CuyScout

Base: d32d0da. Cada modelo (gpt-5.6-luna / gpt-5.6-terra, razonamiento medium)
trabaja en una tarea projectless nueva y un simulador nuevo. Se ejecutan secuencialmente
para limitar carga de la Mac. Solo HTTP a través del proxy, sin guías, código, capturas
ni resultados anteriores. Misma autorización de pagos DEMO local, sin dinero real.

Máximo 80 llamadas / 480 segundos, con corte inmediato ante errores de servidor;
los fallos se conservan y no se convierten en ventajas de eficiencia. Se miden tokens
de tráfico cl100k_base, no tokens totales del modelo ni dinero. Los replays se miden
por separado, con tope de 200 llamadas / 180 segundos y un simulador limpio.

Diferencia respecto de la matriz anterior: ahora se pide conservar el exportado
standalone original y sus parámetros, sin adaptación manual; esa capacidad es parte
del producto corregido. Los agentes deben descubrir su uso a través de /agent-help.
No se repiten las celdas Appium, conforme al foco del usuario en CuyScout.

Luna: 23D157E7-83C2-4AC9-AC3F-52D5CC87A148.
Terra: 0B3C35DE-2A04-4624-9DEB-2599AFE3DEC4.
