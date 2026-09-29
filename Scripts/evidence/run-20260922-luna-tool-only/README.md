# Luna sin guía — 2026-09-22

- Código evaluado: `d57a03c` (checkpoint previo: `a625689`).
- Modelo solicitado: `gpt-5.6-luna`, razonamiento `medium`.
- Tarea independiente: `01a0c913-3287-73d1-9fb5-911225a1e391`.
- Simulador nuevo: `E37F865F-E2DE-48ED-B1BA-3BFE09013AC6`, iPhone 17 Pro, iOS 26.5.
- Transporte: MCP JSON-RPC por ejecutable stdio, con gateway HTTP remoto local. No integración MCP nativa de Codex.
- Gateway: 4724; proxy medidor exclusivo de Luna: 4802.
- Sin acceso autorizado al código fuente, AGENT-GUIDE.md, skills, resultados previos ni screenshots.
- Objetivo: login demo, pago Sedapal suministro 19891201, verificar resumen antes del pago y operación/monto después, exportar prueba TypeScript y cerrar sesión.
- No se autoriza repetir el pago para comprobar el archivo exportado.

La medición usa el mismo meter.py y cl100k_base del benchmark Sonnet. Cuenta tráfico HTTP reenviado, no tokens reales del modelo ni toda la envoltura MCP. initialize, tools/list y ayuda local MCP no atraviesan el proxy y quedan fuera de esta métrica. Por estas diferencias, la comparación histórica no es un A/B controlado.

El coordinador comprobó /status directamente en 4724, fuera del medidor, sin interactuar con la app.

## Resultado

Tarea completada en 347.397 s. Pago DEMO verificado en respuestas MCP: suministro 19891201, monto S/ 50.00, operación SP819334. Resumen observado antes del pago y comprobante después; sesión cerrada con DELETE exitoso.

| Métrica de tráfico HTTP | Luna (esta corrida) | Sonnet (histórico 20260921) |
| --- | ---: | ---: |
| Llamadas | 24 | 23 |
| Tokens de respuesta | 4189 | 4084 |
| Tokens de petición | 1297 | 915 |
| Total cl100k_base | 5486 | 4999 |
| Tiempo acumulado de peticiones | 28.3 s | 50.6 s |

El total incluye el fallo de instalación y status. Los IDs de sesión del adaptador MCP están URL-encoded, otra diferencia en tokens respecto al histórico. No es consumo facturado del modelo ni comparación controlada de rendimiento.

Entregable original de Luna: `/Users/oswaldoleon/Documents/Codex/2026-09-22/sedapal-luna-tool-only/outputs/cuyscout-luna.ts`. Derivado de la exportación Appium/TypeScript y completado con variables/aserciones. No reproducido para evitar un segundo pago; no se certifica su ejecución. La revisión estática del coordinador detectó que conserva un segundo tap incondicional en Sedapal: podría fallar si el primer tap ya abre el formulario. No se alteró el original para ocultar esta limitación.

## Incidente de instalación

El primer POST /session falló: iOS indicó ejecutable ausente. El coordinador comprobó que el IPA sí contiene `Payload/CuyWallet.app/CuyWallet`, pero el directorio de caché temporal `CuyScoutInstallers/CuyWallet.ipa-606498-1788317659/Payload/CuyWallet.app` solo contenía Assets.car e Info.plist. resolveInstaller reutiliza esa caché sin comprobar el ejecutable.

Se verificó con simctl install que `.build/installers/CuyWallet.app` se instala correctamente, sin lanzar ni navegar la app. Se pasó a Luna únicamente esa ruta alternativa. La corrida queda asistida en infraestructura, no en navegación. No se modificó el código evaluado ni se borró la caché.
