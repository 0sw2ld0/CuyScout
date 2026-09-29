# Verificación de código y originales

Código CuyScout `043f12d`: `swift test` termina 0 con 211 pruebas aprobadas; `python3 -m unittest discover -s Tests/Conformance -p test_benchmark_guard.py` termina 0 con 6 pruebas; `http_agent_contract.py` y `mcp_agent_contract.py` terminan 0.

Segunda reparación `51c3bb6`: `swift test` vuelve a pasar 211 pruebas y ambos contratos pasan. El helper original aislado fallaba con TS2322 por `ChainablePromiseElement` vs `WebdriverIO.Element`; al devolver `element.getElement()` pasa `tsc --noEmit` con la misma versión de WebdriverIO/TypeScript. Esta corrección es del producto y no modifica los originales ya archivados.

Originales copiados byte a byte desde los directorios de salida de cada tarea. Las copias de ejecución `.mts` solo cambian de nombre/extensión para cargar ESM.

Entorno de reproducción: Node local, WebdriverIO 9.32.0, tsx 4.23.15, TypeScript 7.0.2, Appium 3.2.2, XCUITest 10.32.0, iOS 26.5, iPhone 17 Pro.

Comprobación estática:

```sh
.build/luna-replay/node_modules/.bin/tsc --noEmit --target es2022 --module nodenext --moduleResolution nodenext --skipLibCheck .build/luna-replay/appium-terra-original.mts
```

Mismo comando para cada original. Los mensajes completos y códigos de salida se conservan en `typecheck-*.txt`.

Reproducción Terra/Appium: WDA precalentado creando/cerrando sesión `a5762d2a-6dc5-4ba3-a927-6f7b4e5f2f92`, sin navegar. Nueva app instalada en `C3D0D027-A1C3-451B-9378-CC5FFE6C22F9`. Proxy separado puerto 4828 con 80 llamadas / 120 segundos. Comando:

```sh
APPIUM_HOST=127.0.0.1 APPIUM_PORT=4828 IOS_UDID=C3D0D027-A1C3-451B-9378-CC5FFE6C22F9 IOS_BUNDLE_ID=com.cuywallet.app .build/luna-replay/node_modules/.bin/tsx .build/luna-replay/appium-terra-original.mts
```

Salida real, código 1:

```text
ReferenceError: $ is not defined
    at main (.../.build/luna-replay/appium-terra-original.mts:37:5)
    at process.processTicksAndRejections (node:internal/process/task_queues:103:5)
```

La ejecución llegó a crear sesión y fijar timeout, falló antes del primer campo de login y ejecutó DELETE en `finally`. No hubo repetición del pago exploratorio. Los dos scripts parciales no se reprodujeron como pagos: su propio código no implementa un flujo completo y ambos agentes habían recibido rechazos de seguridad que no se eludieron.

## Repeticiones tras `51c3bb6`

- Luna/Appium intento 2: TS2322 por capabilities `alwaysMatch` sin `firstMatch`; volvió a recibir rechazo de seguridad en el pago. Original parcial, sin aserciones del recibo; no se reprodujo.
- Luna/CuyScout intento 3: TypeScript pasa. Replay en `EB7EBFD7-B102-4FF3-9A22-F3461918A34D`, puerto 4828, 200 llamadas/180 s, terminó código 1: el resumen fue localizado pero `displayed` devolvió false durante 10 s. Se cerró la sesión sin pagar. Log separado: 117 llamadas, 6 981 tokens. Prewarm sin navegación: `3baef695-3410-4555-861e-1a1eee0bb4cc`.
- Terra/CuyScout intento 3: TypeScript pasa. Replay en `F82A8D59-A278-4D34-B843-99D52FE80322`, puerto 4828, 200 llamadas/180 s, terminó código 1: `btn_service_pay` fue localizado pero `displayed` devolvió false; el controlador cortó al llegar a 200 peticiones. El SDK agotó reintentos acotados de lectura; DELETE fue permitido y la sesión cerró. 201 llamadas medidas incluyendo cierre, 10 808 tokens. No hubo pago en el replay. Prewarm sin navegación: `04027021-09a2-4fb1-b2aa-d63e71df2dac`.

Los comandos de replay usan `APPIUM_HOST=127.0.0.1`, `APPIUM_PORT=4828`, `IOS_BUNDLE_ID=com.cuywallet.app`, el UDID indicado y `tsx .build/luna-replay/TOOL-MODEL-attempt3-original.mts`. Salidas en `replay-*-output.txt` y tráfico completo en sus `.jsonl`; las salidas del terminal pueden estar truncadas por el límite de captura, el medidor no lo está. Las compilaciones se registran en `typecheck-*-attempt*.txt`.
