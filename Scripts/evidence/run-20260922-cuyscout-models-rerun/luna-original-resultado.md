# Resultado de la prueba CuyScout / CuyWallet DEMO

## Estado

No se pudo iniciar la sesión Appium. El controlador HTTP rechazó `POST /session` con:

```text
HTTP 400 Bad Request
{"value":{"error":"invalid argument","message":"No se encontró un simulador disponible"}}
```

La respuesta fue observada tras la solicitud de creación de sesión. Al no existir un `sessionId` válido, no se ejecutaron inicio de sesión, selección de Sedapal, consulta del suministro, elección de monto ni confirmación. Por tanto, no hubo pago, recibo ni número de operación que verificar.

## Limitaciones

- No se generó un artefacto TypeScript de grabación porque la sesión no llegó a crearse; por ello `cuyscout-luna.ts` no está disponible.
- No se realizó ninguna confirmación ni se intentó repetir una operación.
- No se pudo ejecutar `DELETE /session/:id` porque el controlador no devolvió un `sessionId`.
- El monto elegido, operación y métricas quedan sin determinar.
