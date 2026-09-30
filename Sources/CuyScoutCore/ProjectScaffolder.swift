import Foundation

/// Generates the file layout an agent needs to drive an app with CuyScout end to end:
/// setup scripts (ensure the gateway is up, open/close one session per scenario), a
/// credentials fixture and an AGENTS.md tying them together. `cuyscout init` writes
/// these to disk; it never touches `features/` — that's the caller's own authored
/// content, not something CuyScout can generate. Tests only check the generated
/// strings, since the scaffold itself never touches a device.
public enum ProjectScaffolder {
    public struct Options {
        public var appName: String
        public var appPath: String
        public var cuyscoutRepoPath: String
        public var port: Int
        /// Agrega a AGENTS.md las herramientas MCP (`cuyscout_*`); sin esto, solo HTTP/curl.
        public var useMCP: Bool

        public init(appName: String, appPath: String, cuyscoutRepoPath: String, port: Int = 4723, useMCP: Bool = false) {
            self.appName = appName
            self.appPath = appPath
            self.cuyscoutRepoPath = cuyscoutRepoPath
            self.port = port
            self.useMCP = useMCP
        }

        /// A valid shell/env-var identifier derived from `appName` (e.g. "Cuy Wallet 2" -> "CUY_WALLET_2").
        var envPrefix: String {
            let upper = appName.uppercased()
            let sanitized = upper.map { $0.isLetter || $0.isNumber ? $0 : "_" }
            let joined = String(sanitized)
            return joined.first?.isNumber == true ? "_" + joined : joined
        }
    }

    /// Relative path -> file content, for the parts of the project CuyScout owns and
    /// regenerates on every `init`: the setup scripts. Callers decide separately
    /// whether to create `fixtures/credentials.test.json` (only if missing) and how
    /// to merge `agentsMarkdown(for:)` into an existing `AGENTS.md`.
    public static func files(for options: Options) -> [String: String] {
        [
            "scripts/cuyscout-connection.sh": connectionProfile(),
            "scripts/ensure-cuyscout.sh": ensureCuyScout(options),
            "scripts/open-session.sh": openSession(options),
            "scripts/close-session.sh": closeSession(),
            "scripts/replay-cuyscout.sh": replayCuyScout(options),
            "fixtures/replay-values/.gitignore": "*\n!.gitignore\n",
            "rules/README.md": ProjectRuleFile.readme
        ]
    }

    /// Paths (relative to the project root) that should be marked executable after writing.
    public static let executablePaths = [
        "scripts/ensure-cuyscout.sh", "scripts/open-session.sh", "scripts/close-session.sh", "scripts/replay-cuyscout.sh"
    ]

    /// Seed content for `fixtures/credentials.test.json`. Callers write this only when
    /// the file doesn't already exist — never overwrite credentials someone filled in.
    public static func credentialsFixture() -> String {
        #"""
        {
          "demo_user": {
            "email": "demo@example.com",
            "password": "changeme"
          }
        }

        """#
    }

    /// Markers delimiting the block `cuyscout init` owns inside AGENTS.md. Content
    /// outside these markers (added by hand) is preserved across re-runs.
    public static let agentsMarkdownStartMarker = "<!-- cuyscout:init:start -->"
    public static let agentsMarkdownEndMarker = "<!-- cuyscout:init:end -->"

    /// The managed AGENTS.md block: general-purpose instructions for any agent that
    /// opens this project, covering both ways to run a scenario in `features/` —
    /// driving CuyScout fresh (to author/record a new one) or replaying an already
    /// exported `output/*.ts` with plain Appium/WebdriverIO, or replay the saved
    /// `output/*.cuyscout.json` artifact through the CuyScout gateway.
    /// Cómo se conecta el agente al gateway. Por defecto solo HTTP/curl, que funciona en
    /// cualquier Mac; con `useMCP` se agregan las herramientas `cuyscout_*` como vía principal.
    static func connectionSection(useMCP: Bool) -> String {
        useMCP ? mcpConnection : httpConnection
    }

    private static let httpConnection = #"""
## Conexión del agente (misma sesión que CuyScout.app)

Usa el gateway de CuyScout por **HTTP/curl**; no uses otra implementación ni abras un
segundo servidor. El script `scripts/cuyscout-connection.sh` carga URL y token del perfil
privado que escribe CuyScout.app (las variables `CUYSCOUT_URL` y `CUYSCOUT_TOKEN`
explícitas prevalecen); no inventes un token.

```bash
source scripts/cuyscout-connection.sh
curl -fsS -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "${CUYSCOUT_URL}/sessions"
# Si no hay sesión de este proyecto: SESSION=$(scripts/open-session.sh)
curl -fsS -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "${CUYSCOUT_URL}/session/${SESSION}/readiness"
curl -fsS -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "${CUYSCOUT_URL}/session/${SESSION}/observe?maxActions=20"
curl -fsS -X POST -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" -H 'Content-Type: application/json' --data-binary "${SCOUT_ACTION}" "${CUYSCOUT_URL}/session/${SESSION}/actions"
```

Consulta `/sessions` primero: si el usuario ya pulsó **Grabar prueba** en la app, toma
el `sessionId` de esa sesión, comprueba `readiness` y continúa con `observe` →
`actions`. Si no hay una sesión de este proyecto, abre **una** con
`scripts/open-session.sh`, sin variables delante: elige solo el driver (simulador o
iPhone físico), usa la app ya instalada sin relanzarla cuando el proyecto trae
`physicalBundleId`, y pasa `cuyscout:projectDir` para que las reglas de `rules/`
lleguen en cada `observe` y lo que aprendas se guarde ahí.

Conserva el `sessionId` original; no repitas una creación de resultado incierto ni
cierres sesiones de otro agente. Una sesión con `leaseExpired: true` en `/sessions`
(o `session_lease_expired` en readiness) está muerta: no la reutilices; abre una nueva.

`SCOUT_ACTION` debe ser solo `observe.actions[i].action` con los valores de entrada
resueltos y JSON serializado, nunca la sugerencia completa ni un selector inventado.
Si ya existe una sesión, define `SESSION` con su ID y no vuelvas a ejecutar
`open-session.sh`.
"""#

    private static let mcpConnection = #"""
## Conexión del agente (misma sesión que CuyScout.app)

Usa **MCP primero** si el cliente ofrece herramientas `cuyscout_*` conectadas al
gateway. `cuyscout-mcp` lee automáticamente el perfil privado que escribe
CuyScout.app; no inventes un token ni abras un segundo servidor. Si aún no
está configurado en el cliente, el ejecutable stdio viene en
`/Applications/CuyScout.app/Contents/MacOS/cuyscout-mcp`. Llama
`cuyscout_list_sessions`: si el usuario ya pulsó **Grabar prueba** en la app,
toma el `sessionId` de esa sesión, comprueba `cuyscout_session_readiness` y
continúa con `cuyscout_observe` → `cuyscout_execute`. Si no hay una sesión
de este proyecto, crea **una** con `cuyscout_create_session` usando
`driverId: "ios-device"` para iPhone físico o `ios-simulator` para simulador,
`appPath` del instalador correspondiente en `.cuyscout-project.json` y sin
`deviceId` para selección
automática. Si para iPhone no hay instalador pero `.cuyscout-project.json` trae
`physicalBundleId`, la app ya está instalada: crea la sesión con
`bundleIdentifier` (MCP) o `appium:bundleId` (HTTP), `noReset: true` y **sin**
`appPath`; CuyScout la usa tal cual, sin reinstalarla ni relanzarla. Pasa siempre
`projectDir` (MCP) o `cuyscout:projectDir` (HTTP) con la ruta absoluta de este
proyecto: así las reglas de `rules/` llegan en cada `observe` y lo que aprendas se
guarda ahí. `scripts/open-session.sh` ya hace todo esto y elige solo el driver.
Conserva el `sessionId` original; no repitas una creación de
resultado incierto ni cierres sesiones de otro agente. Una sesión con
`leaseExpired: true` en `/sessions` (o `session_lease_expired` en readiness) está
muerta: no la reutilices; abre una nueva.

Si MCP no está disponible o no puede conectarse, usa el **mismo gateway por
HTTP/curl**, no una implementación distinta. El script
`scripts/cuyscout-connection.sh` carga URL y token del perfil privado de la
app (las variables `CUYSCOUT_URL` y `CUYSCOUT_TOKEN` explícitas prevalecen):

```bash
source scripts/cuyscout-connection.sh
curl -fsS -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "${CUYSCOUT_URL}/sessions"
# Si no hay sesión de este proyecto: SESSION=$(scripts/open-session.sh)
curl -fsS -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "${CUYSCOUT_URL}/session/${SESSION}/readiness"
curl -fsS -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "${CUYSCOUT_URL}/session/${SESSION}/observe?maxActions=20"
curl -fsS -X POST -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" -H 'Content-Type: application/json' --data-binary "${SCOUT_ACTION}" "${CUYSCOUT_URL}/session/${SESSION}/actions"
```

`SCOUT_ACTION` debe ser solo `observe.actions[i].action` con los valores de
entrada resueltos y JSON serializado, nunca la sugerencia completa ni un
selector inventado. Si ya existe una sesión, define `SESSION` con su ID y
no vuelvas a ejecutar `open-session.sh`. Cambiar de MCP a curl **no** crea
ni repite una acción: consulta `/sessions` y la observación actual primero.
"""#

    public static func agentsMarkdownBlock(for options: Options) -> String {
        let guide = options.cuyscoutRepoPath.isEmpty
            ? "Consulta el contrato disponible en GET /help del gateway CuyScout antes de empezar."
            : "Lee AGENT-GUIDE.md del repo de CuyScout (\(options.cuyscoutRepoPath)/AGENT-GUIDE.md) antes de empezar."
        return #"""
        \#(agentsMarkdownStartMarker)
        # Pruebas de \#(options.appName) con CuyScout

        Este proyecto prueba **\#(options.appName)** (iOS) sin acceso a su código fuente,
        solo con su instalador. Los escenarios de negocio viven en `features/*.feature`.
        Los scripts y fixtures los genera `cuyscout init` o la interfaz CuyScout.app;
        no los edites a mano salvo `fixtures/credentials.test.json`.
        `.cuyscout-project.json` guarda las rutas de instaladores por tipo de dispositivo;
        CuyScout.app lo actualiza al elegir una `.app` o `.ipa`.

        Hay tres modos para trabajar un escenario de `features/`:

        - **Generar con CuyScout** — cuando el `.feature` es nuevo o cambió y no hay un
          `output/<escenario>.ts` vigente. Un agente conduce la app con el bucle
          observe → decidir → ejecutar y, al cerrar la sesión, exporta el script
          reproducible.
        - **Reproducir con CuyScout** — cuando `output/<escenario>.cuyscout.json` ya
          existe. Importa el artefacto en el gateway y llama a `/artifacts/<id>/replay`;
          no necesita Node, `npm install` ni WebdriverIO.
        - **Reproducir con Appium/WebdriverIO** — cuando `output/<escenario>.ts` ya
          existe y solo quieres confirmar que la app lo sigue pasando. Este camino
          necesita Appium con el driver XCUITest.

        No mezcles los dos: si ya hay un `.ts` exportado para el escenario, reprodúcelo;
        solo generes de nuevo si el `.feature` cambió.

        ## Escribir un escenario (`features/`)

        Si te piden una prueba nueva a partir de una descripción («prueba que pague X con
        85.50»), redacta el `.feature` con estas reglas, guárdalo en `features/` y **espera a
        que lo revisen antes de ejecutarlo**. No modifiques un `.feature` existente sin que lo
        pidan: es la especificación de negocio, no un borrador del agente.

        - **Un `Scenario` por archivo** y un archivo por prueba (`features/<nombre-en-kebab>.feature`):
          cada escenario es una sesión y un artefacto de CuyScout.
        - **Credenciales por alias**, nunca en claro: `Given el usuario "<alias>" ha iniciado
          sesión`. El alias debe existir en `fixtures/credentials.test.json`; si falta, avisa
          y pide los datos — no los inventes.
        - **Cada valor, explícito**: origen, destino, monto, servicio, código… Escribe el valor
          («la cuenta "Ahorros"», «el monto "100.00"»), no «una cuenta» ni «el monto». Lo que la
          app trae preseleccionado no cuenta como elegido.
        - **Restricciones verificables**: «una cuenta destino distinta de la de origen», no
          «otra cuenta». Si un valor puede variar, dilo («cualquier cuenta distinta de …»).
        - **Un `Then` verificable antes de cada acción irreversible** (confirmar, pagar,
          transferir, borrar) que liste lo que debe verse en pantalla, y otro al final con la
          evidencia del resultado («debo ver un número de operación y el monto "S/ 100.00"»).
        - **Solo lenguaje de negocio**: sin selectores, identificadores, coordenadas, esperas
          ni pasos técnicos. CuyScout descubre cómo hacerlo; el `.feature` dice qué y qué se
          espera ver.
        - **Datos variables por fixture o `Examples`**, no copiados de producción: nada de
          datos personales reales.

        Plantilla:

        ```gherkin
        Feature: <Capacidad de negocio>

          Background:
            Given el usuario "<alias>" ha iniciado sesión en <App>

          Scenario: <Resultado concreto que se prueba>
            When <inicio la operación>
            And selecciono <campo> "<valor>"
            And ingreso <campo> "<valor>"
            Then verifico en pantalla que <campo>, <campo> y <campo> coinciden con lo solicitado antes de confirmar
            When confirmo <la operación>
            Then debo ver <evidencia del resultado> y <valor> en la pantalla de resultado
        ```

        \#(connectionSection(useMCP: options.useMCP))

        ## Modo generar (CuyScout)

        1. \#(guide)
        2. Usa la sesión que CuyScout.app ya creó, o abre una nueva — una por
           escenario, nunca reutilices una sesión entre `Scenario`:
           ```bash
           SESSION=$(scripts/open-session.sh)
           ```
        3. Lee el `.feature` objetivo, las reglas de `rules/` y resuelve credenciales del
           `Given` leyendo `fixtures/credentials.test.json` por nombre lógico, nunca
           hardcodeadas. Si el `.feature` no nombra un alias y el fixture tiene uno solo,
           usa ese. Llama `observe` sobre `$SESSION` antes de cada decisión; nunca inventes
           selectores ni coordenadas.
        4. Antes de una acción irreversible (pago, transferencia, borrado), contrasta
           los `texts` de `observe` contra la tabla de verificación del escenario. Si no
           coincide, detente y repórtalo — no confirmes "a ver qué pasa".
        5. Cierra la sesión (valida el plan, exporta a `output/`, borra la sesión):
           ```bash
           scripts/close-session.sh "$SESSION" <nombre-del-escenario>
           ```
           Si la corrida **no llegó a probar el escenario**, no exportes una grabación
           incompleta: ciérrala con `--discard` y el motivo (`servicio_no_disponible`,
           `entorno`, `dispositivo`, `fallo_app` u otro) y el paso donde se detuvo:
           ```bash
           scripts/close-session.sh "$SESSION" <nombre-del-escenario> --discard --reason servicio_no_disponible --step "Given el usuario ha iniciado sesión"
           ```
           Nunca borres la sesión con `curl -X DELETE`: el cierre deja registrado el
           resultado en `output/<escenario>.last-run.json` para el equipo y CuyScout.app.

           Ese cierre genera también `output/<nombre-del-escenario>.cuyscout.json`,
           que es el paquete ejecutable por CuyScout.

        ## Alcanzar las precondiciones

        Los `Given` describen el **estado** del que parte el escenario, no los pasos para
        llegar. "El usuario ha iniciado sesión" significa: observa dónde está la app y haz
        lo necesario para llegar a ese estado. El `.feature` no tiene que explicarlo.

        - **Observa primero y decide por lo que ves.** La app puede abrir en una pantalla de
          bienvenida, de opciones, de login o ya dentro. Consulta `rules/` por si ya se
          resolvió antes.
        - **Usuario recordado.** Si la pantalla ya muestra un usuario, cuenta o nombre
          guardado, no busques un campo de usuario o email: elige la opción de ingresar con
          clave y usa solo la `password` del alias. Usa del fixture solo los campos que la
          pantalla pide.
        - **Botón no es campo.** Un texto como "Ingresa tu clave" en un botón, celda u opción
          no es un campo editable. Escribe solo en elementos `textField`, `secureTextField`,
          `searchField` o `textView` de `observe`. Si solo ves el botón, tócalo, vuelve a
          observar y escribe en el campo que aparezca. CuyScout rechaza escribir en un
          elemento no editable con `not_editable` sin tocarlo.
        - **Pantallas con tiempo límite.** Algunas apps cierran o bloquean una pantalla si
          tardas en elegir. Cuando la siguiente acción es clara, ejecútala justo después
          del `observe`, sin consultas intermedias.
        - **Nada de atajos.** Toma el camino que pide el escenario. Descarta ofertas, tutoriales
          o avisos que no forman parte del flujo (ciérralos con la opción menos invasiva).
        - **Errores del servicio.** Una pantalla como "inténtalo más tarde" o "algo salió
          mal" con un botón de reintentar es un problema del entorno, no de la prueba. Espera
          unos 10 segundos y reintenta **como máximo 2 veces**; si sigue igual, detente y
          reporta "servicio no disponible" con los textos de la pantalla y cierra con
          `scripts/close-session.sh "$SESSION" <escenario> --discard --reason servicio_no_disponible --step "<Given o paso>"`
          (no exporta nada y deja el resultado en `output/<escenario>.last-run.json`). No cambies de camino
          (por ejemplo, a otro canal que ofrezca la app) para esquivarlo. CuyScout rechaza con
          `retry_limit_reached` la misma acción repetida sobre la misma pantalla sin cambios.
        - Si tras dos intentos razonables no alcanzas la precondición, detente y describe
          lo que ves; no improvises acciones irreversibles.

        ## Reglas aprendidas (`rules/`)

        `rules/` guarda lo que los agentes aprendieron de **esta** app: cómo alcanzar una
        precondición, cómo es una pantalla, qué evitar. Se versiona con el proyecto y el
        equipo lo revisa en el diff.

        - **Leer:** antes de empezar, lee `rules/*.md`. Con `projectDir` en la sesión,
          `observe` también devuelve las reglas relevantes en `lessons`.
        - **Guardar:** cuando resuelvas un obstáculo que no estaba en `rules/` (una pantalla
          inesperada, un control engañoso, un orden de pasos necesario), guárdalo al terminar
          el paso, sin datos sensibles:
          ```bash
          curl -fsS -X POST -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" -H 'Content-Type: application/json' \
            -d '{"scope":"project","sessionId":"'"${SESSION}"'","title":"Ingreso con usuario recordado","observation":"La app abre en una pantalla de opciones con el usuario guardado","recommendation":"Tocar la opción de ingresar con clave y escribir solo la password del alias","tags":["login","precondicion"]}' \
            "${CUYSCOUT_URL}/lessons"
          ```
          Mismo título = misma regla: CuyScout la actualiza en vez de duplicarla.
        - **Retroalimentar:** si seguiste una regla, informa si ayudó (`outcome: helped`) o
          no (`failed`); las que fallan dejan de entregarse:
          ```bash
          curl -fsS -X POST -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" -H 'Content-Type: application/json' \
            -d '{"outcome":"helped","sessionId":"'"${SESSION}"'"}' "${CUYSCOUT_URL}/lessons/rule:<id>/feedback"
          ```
        - **Nunca** guardes credenciales, números de cuenta, nombres de clientes ni otros
          datos personales en una regla; CuyScout los filtra, pero no dependas de eso.

        ## Errores de CuyScout y qué hacer

        Cada error de CuyScout trae `hint` con el siguiente paso; síguelo antes de reintentar.

        | Error | Qué significa | Qué hacer |
        | --- | --- | --- |
        | `element not interactable` / `not_editable` | Pediste escribir en algo que no es un campo | No reintentes. Toca el control si lleva al campo, observa y escribe en el campo real |
        | `no such element` | El selector no existe en la pantalla actual | Observa de nuevo y usa un selector de `actions` |
        | `session_lease_expired` | La sesión caducó por inactividad (15 min) | Ciérrala y abre una nueva; no se recupera |
        | `retry_limit_reached` | Repetiste la misma acción en la misma pantalla sin cambios | Si es un error del servicio, detente y repórtalo; si no, observa y elige otra acción |
        | `xctest_runner_starting` | El runner aún arranca | Espera a que readiness quede sin bloqueos |
        | `device_locked` (readiness) | El iPhone está bloqueado y el runner no puede arrancar | Pide a la persona que lo desbloquee; no recrees la sesión |
        | `app_ui_loading` (readiness) | La app aún no muestra controles ni textos | Espera y vuelve a consultar readiness; no observes todavía |
        | "No apareció el teclado" | El campo no abrió el teclado del sistema | Observa: puede que la pantalla cambiara; no reintentes a ciegas |
        | `invalid session id` | La sesión ya no existe | Consulta `/sessions`; abre una nueva si no hay otra de este proyecto |

        | `physical_gateway_not_configured` / `open-session.sh` sale con código 3 | El gateway está en modo local y el escenario usa un iPhone físico | Sigue el mensaje: abre CuyScout.app o cierra el gateway indicado y vuelve a ejecutar; no lo arregles a mano |

        **Diagnóstico.** CuyScout registra arranque, configuración, sesiones, runner y errores en
        `~/Library/Logs/CuyScout/gateway.log` (y la app en `app.log`). Antes de suponer una causa,
        lee las últimas líneas: `curl -fsS -H "Authorization: Bearer ${CUYSCOUT_TOKEN}"
        "${CUYSCOUT_URL}/logs?lines=100"`, y `/doctor` para el estado general (modo iPhone,
        equipo de firma, red). Cita esas líneas al reportar un problema.

        Un error de acción (`not_editable`, `no such element`) no es un fallo de infraestructura:
        nunca lo reintentes con la misma acción. Solo `timeout`/runner/bridge merecen un
        reintento automático.

        ## Modo reproducir con CuyScout

        Ejecuta el escenario con un solo comando. El script levanta el gateway,
        importa el artefacto, prepara la app y hace replay. Al cerrar la grabación,
        CuyScout guardó sus valores concretos en un fixture local ignorado por Git,
        por lo que no tienes que volver a escribirlos:

        ```bash
        scripts/replay-cuyscout.sh <escenario>
        ```

        El argumento acepta el nombre (`transferencia-propia`) o la ruta completa al
        `.cuyscout.json`. `output/` conserva la versión redactada y portable;
        `fixtures/replay-values/<escenario>.json` contiene los datos locales con
        permisos restringidos. Para CI u otro entorno puedes sustituir ese fixture:

        ```bash
        CUYSCOUT_REPLAY_VALUES='{"1.text":"EMAIL","2.text":"PASSWORD","10.text":"MONTO"}' scripts/replay-cuyscout.sh <escenario>
        ```

        En otra Mac el script usa `/Applications/CuyScout.app` si está instalado. Define
        `CUYSCOUT_REPLAY_APP_PATH` con el instalador local. Para elegir simulador y
        preparación, usa `CUYSCOUT_REPLAY_DEVICE_ID` y
        `CUYSCOUT_REPLAY_PREPARATION=preserve|restart|reinstall`. Antes de ejecutar,
        el script comprueba app, runner, fixture y disponibilidad del dispositivo.

        El script equivale a estas operaciones, disponibles para integraciones:

        Antes de usar curl, ejecuta source scripts/cuyscout-connection.sh para
        reutilizar la URL y el token del gateway activo.

        1. Importa el paquete exportado junto al escenario:
           ```bash
           IMPORTED=$(curl -sf -X POST "${CUYSCOUT_URL}/artifacts/import" -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" -H 'Content-Type: application/json' --data-binary @output/<escenario>.cuyscout.json)
           SESSION=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionID"])' <<<"$IMPORTED")
           ```
        2. Ejecuta la prueba grabada sin Node ni Appium:
           ```bash
           curl -sf -X POST "${CUYSCOUT_URL}/artifacts/${SESSION}/replay" -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" -H 'Content-Type: application/json' -d '{"resetApp":true,"resilient":true,"variables":{"1.text":"EMAIL","2.text":"PASSWORD","10.text":"MONTO"}}'
           ```

           Los índices son cero-based y corresponden a las acciones del artefacto;
           si todos los placeholders comparten un valor también puedes usar `redacted`
           o `text` como fallback global.

        ## Modo reproducir (Appium/WebdriverIO)

        1. Verifica Appium arriba (ajusta el puerto al que uses):
           ```bash
           curl -s http://127.0.0.1:\#(options.port)/status || appium --port \#(options.port) &
           ```
        2. Deja la app en su pantalla inicial (relánzala si quedó a mitad de flujo).
        3. Corre el `.ts` exportado con los valores redactados resueltos por variable de
           entorno:
           ```bash
           CUYSCOUT_REPLAY_AUTHORIZED=yes IOS_UDID=<udid> IOS_BUNDLE_ID=<bundle-id> \
           APPIUM_PORT=\#(options.port) CUYSCOUT_REPLAY_VALUES='{"1.text":"..."}' \
           npx tsx output/<escenario>.ts
           ```
        4. Espera una línea `{"status":"passed"}` por paso grabado y
           `{"status":"replay_completed"}` al final. No reintentes ciegamente una
           acción irreversible que falló; repórtalo.

        ## Reglas que no se negocian

        - Una sesión de CuyScout por escenario: la grabación es 1:1 con la sesión desde
          que se crea hasta que se borra.
        - Credenciales solo en `fixtures/credentials.test.json` o por variable de
          entorno — nunca en el `.feature` ni en el `.ts`.
        - Verifica en pantalla antes de confirmar cualquier acción irreversible.
        - Cada valor que el escenario nombra (cuenta de origen, destino, monto…) se elige de
          forma explícita y se comprueba en el resumen. Un valor preseleccionado por la app no
          cuenta como elegido. Si lo pedido no coincide exactamente con ninguna opción, elige la
          más parecida y dilo; si es ambiguo, detente y pregunta. Nunca declares éxito si un valor
          pedido no se ve en el resumen.

        ## Variables de entorno relevantes

        | Variable | Default | Para qué |
        |---|---|---|
        | `CUYSCOUT_REPO` | `\#(options.cuyscoutRepoPath)` | Dónde correr `swift run cuyscout` si el gateway no está arriba |
        | `CUYSCOUT_PORT` | `\#(options.port)` | Puerto del gateway |
        | `CUYSCOUT_DRIVER_ID` | según el proyecto | `ios-device` si el proyecto solo tiene app para iPhone físico; si no, `ios-simulator` |
        | `CUYSCOUT_DEVICE_ID` | vacío | UDID del iPhone físico elegido |
        | `CUYSCOUT_APP_PATH` | vacío | Instalador firmado para iPhone (`.app` o `.ipa`) |
        | `CUYSCOUT_DEVELOPMENT_TEAM` | detectado | Equipo Apple que firma el runner físico; se detecta en Xcode y el llavero |
        | `CUYSCOUT_DEVICE_GATEWAY_URL` | vacío | URL del Mac accesible desde el iPhone |
        | `CUYSCOUT_TOKEN` | vacío | Token obligatorio para el gateway en red local |
        | `\#(options.envPrefix)_APP_PATH` | `\#(options.appPath)` | Instalador a instalar/lanzar |
        | `CUYSCOUT_BOOT_TIMEOUT` | `60` | Segundos a esperar a que el gateway arranque |
        \#(agentsMarkdownEndMarker)
        """#
    }

    /// Merges `agentsMarkdownBlock(for:)` into `existingContent` (nil if AGENTS.md
    /// doesn't exist yet). Content outside the markers is preserved; content between
    /// them is replaced. If `existingContent` is non-nil but has no markers, the
    /// managed block is appended below it rather than guessing where to overwrite.
    public static func mergedAgentsMarkdown(existingContent: String?, options: Options) -> String {
        let block = agentsMarkdownBlock(for: options)
        guard let existingContent else { return block + "\n" }
        guard let startRange = existingContent.range(of: agentsMarkdownStartMarker),
              let endRange = existingContent.range(of: agentsMarkdownEndMarker) else {
            let separator = existingContent.hasSuffix("\n") ? "\n" : "\n\n"
            return existingContent + separator + block + "\n"
        }
        return String(existingContent[..<startRange.lowerBound]) + block + String(existingContent[endRange.upperBound...])
    }

    private static func connectionProfile() -> String {
        #"""
        #!/usr/bin/env bash
        # CuyScout.app guarda URL/token con permisos 0600. Las variables explícitas
        # siempre tienen prioridad, por ejemplo para CI o un gateway remoto.
        CUYSCOUT_PROFILE="${CUYSCOUT_PROFILE:-${HOME}/Library/Application Support/CuyScout/gateway-connection.json}"
        if [[ -f "${CUYSCOUT_PROFILE}" ]]; then
          PROFILE_URL="$(python3 -c 'import json,os,stat,sys; p=sys.argv[1]; s=os.stat(p); assert stat.S_IMODE(s.st_mode)&0o077==0, "El perfil CuyScout debe ser privado (0600)"; print(json.load(open(p))["url"])' "${CUYSCOUT_PROFILE}")"
          PROFILE_TOKEN="$(python3 -c 'import json,os,stat,sys; p=sys.argv[1]; s=os.stat(p); assert stat.S_IMODE(s.st_mode)&0o077==0, "El perfil CuyScout debe ser privado (0600)"; print(json.load(open(p))["token"])' "${CUYSCOUT_PROFILE}")"
          CUYSCOUT_URL="${CUYSCOUT_URL:-${PROFILE_URL}}"
          CUYSCOUT_TOKEN="${CUYSCOUT_TOKEN:-${PROFILE_TOKEN}}"
          export CUYSCOUT_URL CUYSCOUT_TOKEN
        fi
        """#
    }

    private static func ensureCuyScout(_ options: Options) -> String {
        #"""
        #!/usr/bin/env bash
        # Verifica que el gateway de CuyScout esté arriba y respondiendo en $CUYSCOUT_URL.
        # Si no lo está, prefiere el .app instalado y usa el checkout local como respaldo.
        # Con CUYSCOUT_NEEDS_PHYSICAL=1 (lo pone open-session.sh para un iPhone físico) el
        # gateway debe estar en modo iPhone: escuchando en la IP de esta Mac en la red local,
        # con token. Si no hay gateway, lo arranca así; si hay uno local que arrancó este
        # script y no tiene sesiones, lo reinicia en ese modo.
        set -euo pipefail
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cuyscout-connection.sh"

        CUYSCOUT_REPO="${CUYSCOUT_REPO:-\#(options.cuyscoutRepoPath)}"
        CUYSCOUT_PORT="${CUYSCOUT_PORT:-\#(options.port)}"
        CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        LOG_FILE="${CUYSCOUT_LOG:-/tmp/cuyscout-gateway.log}"
        MAX_WAIT_SECONDS="${CUYSCOUT_BOOT_TIMEOUT:-60}"
        NEEDS_PHYSICAL="${CUYSCOUT_NEEDS_PHYSICAL:-0}"
        PID_FILE=/tmp/cuyscout-gateway.pid
        PROFILE="${CUYSCOUT_PROFILE:-${HOME}/Library/Application Support/CuyScout/gateway-connection.json}"
        START_ENV=()

        # Solo cuenta un servidor que se identifica como CuyScout: Appium también usa el 4723
        # por defecto y responde en /status.
        is_up() {
          curl -sf -m 3 "${1:-${CUYSCOUT_URL}}/status" 2>/dev/null | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("name") == "CuyScout" else 1)' 2>/dev/null
        }
        port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
        # Si el puerto lo ocupa otro programa, CuyScout usa el siguiente libre.
        choose_port() {
          local port="${CUYSCOUT_PORT}"
          if port_busy "${port}"; then
            local owner; owner="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -Fc 2>/dev/null | sed -n 's/^c//p' | head -1)"
            for candidate in $(seq $((port + 1)) $((port + 20))); do
              if ! port_busy "${candidate}"; then
                echo "El puerto ${port} lo usa ${owner:-otro programa}; CuyScout usará ${candidate}."
                CUYSCOUT_PORT="${candidate}"
                return
              fi
            done
            echo "El puerto ${port} lo usa ${owner:-otro programa} y no hay otro libre cerca." >&2
            exit 1
          fi
        }
        write_profile() {
          mkdir -p "$(dirname "${PROFILE}")"
          (umask 077; PROFILE_URL="$1" PROFILE_TOKEN="$2" python3 -c 'import json,os,sys; json.dump({"url": os.environ["PROFILE_URL"], "token": os.environ["PROFILE_TOKEN"]}, open(sys.argv[1], "w"))' "${PROFILE}")
          chmod 600 "${PROFILE}"
        }
        physical_enabled() {
          curl -sf -m 3 "${CUYSCOUT_URL}/status" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("value",{}).get("physical",{}).get("enabled",False))' 2>/dev/null || echo False
        }
        session_count() {
          curl -sf -m 5 ${CUYSCOUT_TOKEN:+-H "Authorization: Bearer ${CUYSCOUT_TOKEN}"} "${CUYSCOUT_URL}/sessions" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "?"
        }
        own_pid() {
          [[ -f "${PID_FILE}" ]] || return 0
          local pid; pid="$(cat "${PID_FILE}")"
          if kill -0 "${pid}" 2>/dev/null; then echo "${pid}"; fi
        }
        is_this_mac() {
          local host; host="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.urlparse(sys.argv[1]).hostname or "")' "$1")"
          [[ "${host}" == "127.0.0.1" || "${host}" == "localhost" ]] || ifconfig | grep -q "inet ${host} "
        }

        # Prepara el arranque en modo iPhone: IP de esta Mac, token nuevo y perfil privado que
        # leen los scripts, el MCP y CuyScout.app.
        prepare_physical() {
          local ip
          ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
          if [[ -z "${ip}" ]]; then
            echo "No se encontró una IP de red local en esta Mac. Conéctala a Wi-Fi o al hotspot del iPhone." >&2
            exit 1
          fi
          choose_port
          local token; token="$(openssl rand -hex 24)"
          CUYSCOUT_URL="http://${ip}:${CUYSCOUT_PORT}"
          CUYSCOUT_TOKEN="${token}"
          START_ENV=(CUYSCOUT_TOKEN="${token}" CUYSCOUT_BIND_ADDRESS="${ip}" CUYSCOUT_DEVICE_GATEWAY_URL="${CUYSCOUT_URL}")
          write_profile "${CUYSCOUT_URL}" "${token}"
          echo "Modo iPhone físico: el runner se conectará a ${CUYSCOUT_URL}$([[ "${ip}" == 172.20.10.* ]] && echo ' (hotspot del iPhone)')."
        }

        # El perfil puede apuntar a una IP de red que ya no responde mientras un gateway local
        # sigue ocupando el puerto: se evalúa ese, en vez de levantar un segundo gateway.
        LOCAL_URL="http://127.0.0.1:${CUYSCOUT_PORT}"
        if ! is_up && [[ "${CUYSCOUT_URL}" != "${LOCAL_URL}" ]] && is_up "${LOCAL_URL}"; then
          CUYSCOUT_URL="${LOCAL_URL}"
        fi

        if is_up; then
          if [[ "${NEEDS_PHYSICAL}" != "1" || "$(physical_enabled)" == "True" ]]; then
            echo "CuyScout ya está arriba en ${CUYSCOUT_URL}"
            exit 0
          fi
          OWN="$(own_pid)"
          SESSIONS="$(session_count)"
          if [[ -n "${OWN}" && "${SESSIONS}" == "0" ]]; then
            echo "El gateway en ${CUYSCOUT_URL} está en modo local; lo reinicio en modo iPhone físico (lo arrancó este script, pid ${OWN}, sin sesiones)."
            kill "${OWN}"
            for _ in $(seq 1 20); do is_up || break; sleep 0.5; done
          else
            echo "El gateway en ${CUYSCOUT_URL} está en modo local y este escenario usa un iPhone físico: el iPhone no podría conectarse." >&2
            echo "Abre CuyScout.app (arranca el gateway en modo iPhone) o cierra ese gateway${OWN:+ (pid ${OWN})} y vuelve a ejecutar. Sesiones abiertas: ${SESSIONS}." >&2
            exit 3
          fi
        elif ! is_this_mac "${CUYSCOUT_URL}"; then
          echo "El gateway compartido no responde en ${CUYSCOUT_URL}. Abre CuyScout.app y pulsa Iniciar gateway; no se iniciará otro servidor para evitar sesiones duplicadas." >&2
          exit 1
        fi

        if [[ "${NEEDS_PHYSICAL}" == "1" ]]; then
          prepare_physical
        else
          # Local con token y perfil: si cambió el puerto, los demás scripts lo encuentran.
          choose_port
          CUYSCOUT_URL="http://127.0.0.1:${CUYSCOUT_PORT}"
          LOCAL_TOKEN="$(openssl rand -hex 24)"
          START_ENV=(CUYSCOUT_TOKEN="${LOCAL_TOKEN}")
          write_profile "${CUYSCOUT_URL}" "${LOCAL_TOKEN}"
        fi

        CUYSCOUT_BIN="${CUYSCOUT_BIN:-}"
        INSTALLED_BIN="/Applications/CuyScout.app/Contents/MacOS/cuyscout"
        if [[ -n "${CUYSCOUT_BIN}" && -x "${CUYSCOUT_BIN}" ]]; then
          echo "Levantando CuyScout desde ${CUYSCOUT_BIN} ..."
          env ${START_ENV[@]+"${START_ENV[@]}"} nohup "${CUYSCOUT_BIN}" "${CUYSCOUT_PORT}" >"${LOG_FILE}" 2>&1 &
          echo $! > "${PID_FILE}"
        elif [[ -n "${CUYSCOUT_REPO}" && -f "${CUYSCOUT_REPO}/Package.swift" ]]; then
          echo "Levantando CuyScout desde ${CUYSCOUT_REPO} ..."
          (
            cd "${CUYSCOUT_REPO}"
            env ${START_ENV[@]+"${START_ENV[@]}"} nohup swift run cuyscout "${CUYSCOUT_PORT}" >"${LOG_FILE}" 2>&1 &
            echo $! > "${PID_FILE}"
          )
        elif [[ -x "${INSTALLED_BIN}" ]]; then
          echo "Levantando CuyScout desde ${INSTALLED_BIN} ..."
          env ${START_ENV[@]+"${START_ENV[@]}"} nohup "${INSTALLED_BIN}" "${CUYSCOUT_PORT}" >"${LOG_FILE}" 2>&1 &
          echo $! > "${PID_FILE}"
        else
          echo "No se encontró CuyScout.app ni el repo. Ajusta CUYSCOUT_BIN o CUYSCOUT_REPO." >&2
          exit 1
        fi

        echo "Esperando a que ${CUYSCOUT_URL}/status responda (timeout ${MAX_WAIT_SECONDS}s, log en ${LOG_FILE} y ~/Library/Logs/CuyScout/gateway.log) ..."
        elapsed=0
        until is_up; do
          if (( elapsed >= MAX_WAIT_SECONDS )); then
            echo "CuyScout no arrancó a tiempo. Revisa ${LOG_FILE} y ~/Library/Logs/CuyScout/gateway.log." >&2
            exit 1
          fi
          sleep 2
          elapsed=$((elapsed + 2))
        done

        echo "CuyScout arriba en ${CUYSCOUT_URL} (pid $(cat "${PID_FILE}" 2>/dev/null || echo '?'))"

        """#
    }

    private static func openSession(_ options: Options) -> String {
        #"""
        #!/usr/bin/env bash
        # Hook "Before" de un Scenario: garantiza CuyScout arriba, abre una sesión NUEVA
        # con el instalador de la app y espera a que esté lista para recibir acciones.
        # Imprime el sessionId por stdout (única línea) para que el agente lo capture.
        set -euo pipefail

        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
        EXPLICIT_URL="${CUYSCOUT_URL:-}"
        source "${SCRIPT_DIR}/cuyscout-connection.sh"
        CUYSCOUT_PORT="${CUYSCOUT_PORT:-\#(options.port)}"
        CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        # Sin CUYSCOUT_DRIVER_ID, el driver sale del proyecto: si solo tiene instalador o app
        # para iPhone físico, se usa ios-device; en cualquier otro caso, el simulador.
        DEFAULT_DRIVER="ios-simulator"
        if [[ -f "${PROJECT_DIR}/.cuyscout-project.json" ]]; then
          DEFAULT_DRIVER="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("ios-device" if not d.get("simulator") and (d.get("physical") or d.get("physicalBundleId")) else "ios-simulator")' "${PROJECT_DIR}/.cuyscout-project.json")"
        fi
        DRIVER_ID="${CUYSCOUT_DRIVER_ID:-${DEFAULT_DRIVER}}"
        DEVICE_ID="${CUYSCOUT_DEVICE_ID:-}"
        PROJECT_APP_PATH=""
        PROJECT_BUNDLE_ID=""
        if [[ -f "${PROJECT_DIR}/.cuyscout-project.json" ]]; then
          PROJECT_APP_PATH="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("physical" if sys.argv[2]=="ios-device" else "simulator", ""))' "${PROJECT_DIR}/.cuyscout-project.json" "${DRIVER_ID}")"
          if [[ "${DRIVER_ID}" == "ios-device" ]]; then
            PROJECT_BUNDLE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("physicalBundleId") or "")' "${PROJECT_DIR}/.cuyscout-project.json")"
          fi
        fi
        # App ya instalada (p. ej. una compilación de desarrollo en el iPhone): sin instalador,
        # se prueba tal como está. Un instalador explícito ($1 o CUYSCOUT_APP_PATH) tiene prioridad.
        BUNDLE_ID=""
        if [[ -z "${1:-}" && -z "${CUYSCOUT_APP_PATH:-}" && -z "${PROJECT_APP_PATH}" ]]; then
          BUNDLE_ID="${CUYSCOUT_BUNDLE_ID:-${PROJECT_BUNDLE_ID}}"
        fi
        APP_PATH="${1:-${CUYSCOUT_APP_PATH:-${PROJECT_APP_PATH:-${\#(options.envPrefix)_APP_PATH:-\#(options.appPath)}}}}"
        if [[ "${DRIVER_ID}" == "ios-device" && -z "${BUNDLE_ID}" && -z "${1:-}" && -z "${CUYSCOUT_APP_PATH:-}" && -z "${PROJECT_APP_PATH}" ]]; then
          echo "Falta instalador firmado para iPhone o una app ya instalada. Elígela en CuyScout.app, o define CUYSCOUT_APP_PATH o CUYSCOUT_BUNDLE_ID." >&2
          exit 1
        fi
        scout_curl() {
          if [[ -n "${CUYSCOUT_TOKEN:-}" ]]; then curl -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "$@"
          else curl "$@"; fi
        }

        if [[ -z "${BUNDLE_ID}" && ! -e "${APP_PATH}" ]]; then
          echo "No existe el instalador en ${APP_PATH}. Compílalo o pasa la ruta correcta como \$1." >&2
          exit 1
        fi

        if [[ "${DRIVER_ID}" == "ios-device" ]]; then export CUYSCOUT_NEEDS_PHYSICAL=1; fi
        "${SCRIPT_DIR}/ensure-cuyscout.sh" >&2
        # ensure-cuyscout.sh puede haber arrancado el gateway en modo iPhone con URL y token
        # nuevos: se relee el perfil salvo que la URL viniera explícita.
        if [[ -z "${EXPLICIT_URL}" ]]; then
          unset CUYSCOUT_URL CUYSCOUT_TOKEN
          source "${SCRIPT_DIR}/cuyscout-connection.sh"
          CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        fi
        if [[ "${DRIVER_ID}" == "ios-device" ]]; then
          PHYSICAL_ISSUES=$(curl -sf -m 5 "${CUYSCOUT_URL}/status" | python3 -c '
        import json, sys
        physical = json.load(sys.stdin).get("value", {}).get("physical", {})
        print("" if physical.get("ready") else " ".join(physical.get("issues") or ["El gateway no informa el modo iPhone físico; actualiza CuyScout."]))
        ' 2>/dev/null || echo "No se pudo consultar ${CUYSCOUT_URL}/status.")
          if [[ -n "${PHYSICAL_ISSUES}" ]]; then
            echo "El gateway no está listo para un iPhone físico: ${PHYSICAL_ISSUES}" >&2
            echo "Detalle en ~/Library/Logs/CuyScout/gateway.log" >&2
            exit 3
          fi
        fi

        SESSION_BODY=$(REPLAY_APP_PATH="${APP_PATH}" REPLAY_BUNDLE_ID="${BUNDLE_ID}" REPLAY_DRIVER_ID="${DRIVER_ID}" REPLAY_DEVICE_ID="${DEVICE_ID}" REPLAY_PROJECT_DIR="${PROJECT_DIR}" python3 -c '
        import json,os
        caps={"platformName":"iOS","appium:automationName":"XCUITest","appium:driverId":os.environ["REPLAY_DRIVER_ID"],"cuyscout:projectDir":os.environ["REPLAY_PROJECT_DIR"]}
        # App ya instalada: la sesión empieza donde esté la app, sin relanzarla.
        if os.environ["REPLAY_BUNDLE_ID"]: caps["appium:bundleId"]=os.environ["REPLAY_BUNDLE_ID"]; caps["appium:noReset"]=True
        else: caps["appium:app"]=os.environ["REPLAY_APP_PATH"]
        if os.environ["REPLAY_DEVICE_ID"]: caps["appium:udid"]=os.environ["REPLAY_DEVICE_ID"]
        print(json.dumps({"capabilities":{"alwaysMatch":caps}}))
        ')
        SESSION_JSON=$(scout_curl -sf -X POST "${CUYSCOUT_URL}/session" -H 'Content-Type: application/json' --data-binary "${SESSION_BODY}")

        SESSION=$(echo "${SESSION_JSON}" | python3 -c '
        import json, sys
        data = json.load(sys.stdin)
        value = data.get("value", data)
        if "sessionId" not in value:
            sys.stderr.write(json.dumps(data) + "\n")
            sys.exit(1)
        print(value["sessionId"])
        ')

        scout_curl -sf -X POST "${CUYSCOUT_URL}/session/${SESSION}/timeouts" \
          -H 'Content-Type: application/json' -d '{"implicit":15000}' >&2

        echo "Esperando readiness de la sesión ${SESSION} ..." >&2
        elapsed=0
        ui_wait=0
        while true; do
          READY=$(scout_curl -sf "${CUYSCOUT_URL}/session/${SESSION}/readiness" | python3 -c '
        import json, sys
        data = json.load(sys.stdin)
        value = data.get("value", data)
        blockers = value.get("blockers", [])
        print("ready" if value.get("interactionReady", False) else ("ui" if blockers == ["app_ui_loading"] else ("locked" if "device_locked" in blockers else "no")))
        ')
          [[ "${READY}" == "ready" ]] && break
          if [[ "${READY}" == "locked" && "${locked_notice:-}" != "1" ]]; then
            echo "El iPhone está bloqueado: desbloquéalo para que arranque el runner (se sigue esperando)." >&2
            locked_notice=1
          fi
          # La app arranca pero aún no dibuja controles ni textos (splash, carga). Se espera
          # un tiempo acotado: una pantalla que solo muestra una imagen también es válida.
          if [[ "${READY}" == "ui" ]]; then
            if (( ui_wait >= 45 )); then
              echo "La app no mostró controles ni textos en ${ui_wait} s; se continúa. Observa antes de actuar." >&2
              break
            fi
            ui_wait=$((ui_wait + 2))
          fi
          if (( elapsed >= 180 )); then
            echo "La sesión ${SESSION} no quedó lista a tiempo${locked_notice:+ (el iPhone siguió bloqueado)}." >&2
            scout_curl -sf -X DELETE "${CUYSCOUT_URL}/session/${SESSION}" >/dev/null || true
            exit 1
          fi
          sleep 2
          elapsed=$((elapsed + 2))
        done

        echo "Sesión ${SESSION} lista en ${CUYSCOUT_URL}" >&2
        echo "${SESSION}"

        """#
    }

    private static func closeSession() -> String {
        #"""
        #!/usr/bin/env bash
        # Hook "After" de un Scenario. Por defecto valida el plan grabado, exporta la prueba
        # (TypeScript y artefacto CuyScout) y borra la sesión. Con --discard NO exporta nada:
        # para corridas que no llegaron a probar el escenario (servicio caído, precondición
        # imposible). En ambos casos deja output/<escenario>.last-run.json con el resultado.
        #
        # Uso: close-session.sh <sessionId> <escenario> [--discard] [--reason <código>] [--step "<paso>"]
        #   --reason: servicio_no_disponible | entorno | dispositivo  → bloqueado por entorno
        #             fallo_app                                     → falló
        #             otro texto                                    → descartado
        set -euo pipefail
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "${SCRIPT_DIR}/cuyscout-connection.sh"

        SESSION="${1:?Uso: close-session.sh <sessionId> <escenario> [--discard] [--reason <código>] [--step \"<paso>\"]}"
        SCENARIO_NAME="scenario"
        if [[ $# -ge 2 && "${2}" != --* ]]; then SCENARIO_NAME="${2}"; shift 2; else shift 1; fi
        DISCARD=false
        REASON=""
        STEP=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --discard) DISCARD=true ;;
            --reason) REASON="${2:-}"; shift ;;
            --step) STEP="${2:-}"; shift ;;
            *) echo "Opción desconocida: $1" >&2; exit 2 ;;
          esac
          shift
        done
        CUYSCOUT_PORT="${CUYSCOUT_PORT:-4723}"
        CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        scout_curl() {
          if [[ -n "${CUYSCOUT_TOKEN:-}" ]]; then curl -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "$@"
          else curl "$@"; fi
        }
        OUT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/output"
        mkdir -p "${OUT_DIR}"

        # Resultado de la corrida para CuyScout.app y el equipo. Los textos de la pantalla
        # se guardan como evidencia, sin correos ni números largos (cuentas, documentos).
        write_last_run() {
          local status_source="$1" texts_json="$2"
          LAST_RUN_SCENARIO="${SCENARIO_NAME}" LAST_RUN_SESSION="${SESSION}" LAST_RUN_REASON="${REASON}" \
          LAST_RUN_STEP="${STEP}" LAST_RUN_SOURCE="${status_source}" LAST_RUN_TEXTS="${texts_json}" python3 -c '
        import json, os, re, datetime
        reason = os.environ["LAST_RUN_REASON"]
        if os.environ["LAST_RUN_SOURCE"] == "recorded":
            status = "recorded"
        elif reason in ("servicio_no_disponible", "entorno", "dispositivo"):
            status = "blocked_environment"
        elif reason == "fallo_app":
            status = "failed"
        else:
            status = "discarded"
        def clean(text):
            text = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "<correo>", text)
            text = re.sub(r"\d{8,}", "<número>", text)
            return text[:160]
        try:
            texts = [clean(t) for t in json.loads(os.environ["LAST_RUN_TEXTS"] or "[]")][:12]
        except ValueError:
            texts = []
        report = {"scenario": os.environ["LAST_RUN_SCENARIO"], "status": status, "sessionId": os.environ["LAST_RUN_SESSION"],
                  "finishedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        if reason: report["reason"] = reason
        if os.environ["LAST_RUN_STEP"]: report["step"] = os.environ["LAST_RUN_STEP"]
        if texts: report["screenTexts"] = texts
        print(json.dumps(report, ensure_ascii=False, indent=2))
        ' > "${OUT_DIR}/${SCENARIO_NAME}.last-run.json"
          echo "Resultado guardado en ${OUT_DIR}/${SCENARIO_NAME}.last-run.json" >&2
        }

        if [[ "${DISCARD}" == "true" ]]; then
          [[ "${SCENARIO_NAME}" != "scenario" ]] || { echo "--discard requiere el nombre del escenario" >&2; exit 2; }
          TEXTS=$(scout_curl -sf "${CUYSCOUT_URL}/session/${SESSION}/observe?maxActions=5" | python3 -c '
        import json, sys
        data = json.load(sys.stdin)
        print(json.dumps(data.get("value", data).get("texts", [])))
        ' 2>/dev/null || echo "[]")
          write_last_run discarded "${TEXTS}"
          scout_curl -sf -X DELETE "${CUYSCOUT_URL}/session/${SESSION}" >/dev/null
          echo "Sesión ${SESSION} cerrada sin exportar (${REASON:-descartada})."
          exit 0
        fi

        echo "Validando el plan grabado de la sesión ${SESSION} ..."
        scout_curl -sf "${CUYSCOUT_URL}/session/${SESSION}/recording/plan/validate" | tee "${OUT_DIR}/${SCENARIO_NAME}.validate.json"

        echo "Exportando prueba reproducible (TypeScript) ..."
        scout_curl -sf "${CUYSCOUT_URL}/session/${SESSION}/recording/appium/typescript" \
          -o "${OUT_DIR}/${SCENARIO_NAME}.ts"
        echo "Prueba exportada en ${OUT_DIR}/${SCENARIO_NAME}.ts"

        echo "Exportando artefacto CuyScout para replay nativo ..."
        scout_curl -sf "${CUYSCOUT_URL}/session/${SESSION}/artifacts" \
          -o "${OUT_DIR}/${SCENARIO_NAME}.cuyscout.json"
        echo "Artefacto exportado en ${OUT_DIR}/${SCENARIO_NAME}.cuyscout.json"

        REPLAY_VALUES_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/fixtures/replay-values"
        mkdir -p "${REPLAY_VALUES_DIR}"
        echo "Guardando valores locales del replay fuera del artefacto ..."
        scout_curl -sf -X POST "${CUYSCOUT_URL}/session/${SESSION}/recording/replay-values" \
          -o "${REPLAY_VALUES_DIR}/${SCENARIO_NAME}.json"
        chmod 600 "${REPLAY_VALUES_DIR}/${SCENARIO_NAME}.json"

        write_last_run recorded "[]"
        scout_curl -sf -X DELETE "${CUYSCOUT_URL}/session/${SESSION}" >/dev/null
        echo "Sesión ${SESSION} cerrada."

        """#
    }

    private static func replayCuyScout(_ options: Options) -> String {
        #"""
        #!/usr/bin/env bash
        # Importa y ejecuta un output/<escenario>.cuyscout.json en una sola orden.
        set -euo pipefail

        TARGET="${1:?Uso: replay-cuyscout.sh <escenario|ruta.cuyscout.json>}"
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "${SCRIPT_DIR}/cuyscout-connection.sh"
        PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
        CUYSCOUT_PORT="${CUYSCOUT_PORT:-\#(options.port)}"
        CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        scout_curl() {
          if [[ -n "${CUYSCOUT_TOKEN:-}" ]]; then curl -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "$@"
          else curl "$@"; fi
        }
        VALUES="${CUYSCOUT_REPLAY_VALUES:-}"
        RESILIENT="${CUYSCOUT_REPLAY_RESILIENT:-false}"
        DEVICE_ID="${CUYSCOUT_REPLAY_DEVICE_ID:-}"
        PREPARATION="${CUYSCOUT_REPLAY_PREPARATION:-restart}"

        if [[ -f "${TARGET}" ]]; then
          ARTIFACT="${TARGET}"
        else
          ARTIFACT="${PROJECT_DIR}/output/${TARGET%.cuyscout.json}.cuyscout.json"
        fi
        [[ -f "${ARTIFACT}" ]] || { echo "No existe el artefacto: ${ARTIFACT}" >&2; exit 1; }
        RECORDED_KIND="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["session"]["device"].get("kind", "simulator"))' "${ARTIFACT}")"
        PROJECT_APP_PATH=""
        PROJECT_BUNDLE_ID=""
        if [[ -f "${PROJECT_DIR}/.cuyscout-project.json" ]]; then
          PROJECT_APP_PATH="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("physical" if sys.argv[2]=="physical" else "simulator", ""))' "${PROJECT_DIR}/.cuyscout-project.json" "${RECORDED_KIND}")"
          PROJECT_BUNDLE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("physicalBundleId") or "")' "${PROJECT_DIR}/.cuyscout-project.json")"
        fi
        if [[ "${RECORDED_KIND}" == "physical" && -z "${CUYSCOUT_REPLAY_APP_PATH:-}" && -z "${PROJECT_APP_PATH}" ]]; then
          if [[ -z "${PROJECT_BUNDLE_ID}" && -z "${CUYSCOUT_BUNDLE_ID:-}" ]]; then
            echo "Falta instalador firmado para iPhone o una app ya instalada. Elígela en CuyScout.app, o define CUYSCOUT_REPLAY_APP_PATH o CUYSCOUT_BUNDLE_ID." >&2
            exit 1
          fi
          # App ya instalada en el iPhone: se reproduce sin reinstalarla.
          APP_PATH=""
        else
          APP_PATH="${CUYSCOUT_REPLAY_APP_PATH:-${PROJECT_APP_PATH:-\#(options.appPath)}}"
        fi
        SCENARIO_NAME="$(basename "${ARTIFACT%.cuyscout.json}")"
        if [[ -z "${VALUES}" && -f "${PROJECT_DIR}/fixtures/replay-values/${SCENARIO_NAME}.json" ]]; then
          VALUES="$(<"${PROJECT_DIR}/fixtures/replay-values/${SCENARIO_NAME}.json")"
        fi
        [[ -n "${VALUES}" ]] || VALUES='{}'

        "${SCRIPT_DIR}/ensure-cuyscout.sh" >&2

        IMPORTED=$(scout_curl -sf -X POST "${CUYSCOUT_URL}/artifacts/import?overwrite=true" \
          -H 'Content-Type: application/json' --data-binary @"${ARTIFACT}")
        SESSION=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionID"])' <<<"${IMPORTED}")

        REQUEST_BODY=$(REPLAY_VALUES="${VALUES}" REPLAY_APP_PATH="${APP_PATH}" REPLAY_RESILIENT="${RESILIENT}" \
          REPLAY_DEVICE_ID="${DEVICE_ID}" REPLAY_PREPARATION="${PREPARATION}" python3 -c '
        import json, os
        values = json.loads(os.environ["REPLAY_VALUES"])
        body = {"preparation": os.environ["REPLAY_PREPARATION"], "resilient": os.environ["REPLAY_RESILIENT"].lower() == "true", "variables": values}
        app_path = os.environ.get("REPLAY_APP_PATH", "")
        if app_path: body["appPath"] = app_path
        device_id = os.environ.get("REPLAY_DEVICE_ID", "")
        if device_id: body["deviceID"] = device_id
        print(json.dumps(body))
        ')
        PREFLIGHT=$(scout_curl -sf -X POST "${CUYSCOUT_URL}/artifacts/${SESSION}/replay/preflight" \
          -H 'Content-Type: application/json' --data-binary "${REQUEST_BODY}")
        python3 -c '
        import json,sys
        report=json.load(sys.stdin)
        for item in report["warnings"]: print("Aviso: " + item, file=sys.stderr)
        if not report["ready"]:
            for item in report["errors"]: print("Error: " + item, file=sys.stderr)
            sys.exit(1)
        print("Preflight listo: " + report["selectedDevice"]["name"], file=sys.stderr)
        ' <<<"${PREFLIGHT}"
        scout_curl -sf -X POST "${CUYSCOUT_URL}/artifacts/${SESSION}/replay" \
          -H 'Content-Type: application/json' --data-binary "${REQUEST_BODY}"
        echo

        """#
    }
}
