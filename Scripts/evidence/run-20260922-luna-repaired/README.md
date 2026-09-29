# Luna: validación de reparaciones (2026-09-22)

Tarea independiente `01a0c920-5a4d-7860-85de-7527f2075064`, modelo solicitado `gpt-5.6-luna`, razonamiento medium. No acceso autorizado a código, guías, skills del proyecto, resultados previos, otros chats ni screenshots. Descubrimiento por initialize/tools/list/cuyscout_help, transporte MCP stdio con CUYSCOUT_GATEWAY_URL al medidor HTTP.

Instalador original `.build/installers/CuyWallet.ipa`; simulador limpio `01D5D570-F880-4962-961A-D75E0EE41EDA` (iPhone 17 Pro / iOS 26.5). Objetivo: login DEMO, pago Sedapal 19891201 con monto elegido por Luna, resumen previo y comprobante posterior. El coordinador no proporciona selectores ni pasos de navegación.

La herramienta reparada comprueba el ejecutable de la caché IPA, usa SHA-256 del contenido y extrae en un directorio privado antes de publicar. La ayuda MCP explica reintentos condicionales de navegación y requisitos de reproducción. El exportador TypeScript agrega esperas de existencia y advertencias sobre la diferencia entre registro de intentos y prueba verificada.

## Verificación independiente del entregable

El prompt solicita TypeScript standalone (tsx/WebdriverIO/node:assert), con parámetros de infraestructura y aserciones. Luna no reproduce ni efectúa un segundo pago en su sesión. El coordinador verificará el archivo original en otra instalación DEMO limpia mediante Appium, sin mezclar ese tráfico con las llamadas de Luna.

- Simulador de reproducción: `9DFA7BD9-08BC-44A8-94CD-857C333CA8A2`.
- Appium 3.2.2, XCUITest driver 10.32.0, puerto 4902, WDA 8102.
- Gateway de exploración 4724, medidor exclusivo de Luna 4802.
- Dependencias de reproducción y lockfile en `.build/luna-replay`.

Medición: mismo meter.py y cl100k_base del histórico Sonnet. Solo tokens del tráfico HTTP reenviado: excluye initialize/tools/list/ayuda local y envolturas MCP. No son tokens facturados ni un A/B controlado.

Resultado: corrida diagnóstica fallida, sin pagos ni entregable. Sesión cerrada. Duración 870.103 s.

Luna atribuyó el error a la escritura segura, pero la revisión del coordinador del JSON-RPC enviado mostró una llave de cierre ausente en sus peticiones de contraseña: el error tenía id:null y no alcanzó el gateway. Los reintentos sobre la UI no podían solucionarlo. La sesión finalmente agotó la vida del runner. Se conservan los resultados sin presentar ese diagnóstico de Luna como causa comprobada.

Durante la corrida se mejoraron los errores de argumentos y después los errores de parseo del ejecutable MCP. Se indicó reiniciar solo el transporte para cargar los cambios. Es una corrida diagnóstica asistida, no un benchmark controlado. La siguiente repetición usa un cliente stdio mínimo que serializa el sobre JSON-RPC y configura el gateway, sin conocimiento de la app ni reintentos automáticos.
