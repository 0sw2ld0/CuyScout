# CuyScout W3C/Appium smoke tests

Requisitos comunes:

1. Iniciar CuyScout.
2. Tener un simulador iOS disponible.
3. Definir `CUYSCOUT_DEVICE_ID`.

HTTP puro:

```bash
CUYSCOUT_DEVICE_ID=SIMULATOR_UDID ./w3c_smoke.sh
```

Cubre status, conformidad, creación de sesión, capabilities, timeouts, registro/heartbeat/baja de workers de device farm y el handshake WebSocket BiDi (`101 Switching Protocols` con el `Sec-WebSocket-Accept` esperado).

Appium Python:

```bash
python3 -m pip install -r requirements.txt
CUYSCOUT_DEVICE_ID=SIMULATOR_UDID python3 appium_python_smoke.py
```

WebdriverIO:

```bash
npm install
CUYSCOUT_DEVICE_ID=SIMULATOR_UDID node webdriverio_smoke.mjs
```

Appium Java (io.appium:java-client 10.1.1, requiere JDK 17+ y Gradle):

```bash
gradle -q -p java-smoke run
```

`CUYSCOUT_URL` y `CUYSCOUT_TOKEN` son opcionales. Los scripts crean y eliminan su propia sesión.
