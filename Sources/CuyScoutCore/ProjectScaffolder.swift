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

        public init(appName: String, appPath: String, cuyscoutRepoPath: String, port: Int = 4723) {
            self.appName = appName
            self.appPath = appPath
            self.cuyscoutRepoPath = cuyscoutRepoPath
            self.port = port
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
            "fixtures/replay-values/.gitignore": "*\n!.gitignore\n"
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
        automática. Conserva el `sessionId` original; no repitas una creación de
        resultado incierto ni cierres sesiones de otro agente.

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

        ## Modo generar (CuyScout)

        1. \#(guide)
        2. Usa la sesión que CuyScout.app ya creó, o abre una nueva — una por
           escenario, nunca reutilices una sesión entre `Scenario`:
           ```bash
           SESSION=$(scripts/open-session.sh)
           ```
        3. Lee el `.feature` objetivo y resuelve credenciales del `Given` leyendo
           `fixtures/credentials.test.json` por nombre lógico, nunca hardcodeadas.
           Llama `observe` sobre `$SESSION` antes de cada decisión; nunca inventes
           selectores ni coordenadas.
        4. Antes de una acción irreversible (pago, transferencia, borrado), contrasta
           los `texts` de `observe` contra la tabla de verificación del escenario. Si no
           coincide, detente y repórtalo — no confirmes "a ver qué pasa".
        5. Cierra la sesión (valida el plan, exporta a `output/`, borra la sesión):
           ```bash
           scripts/close-session.sh "$SESSION" <nombre-del-escenario>
           ```

           Ese cierre genera también `output/<nombre-del-escenario>.cuyscout.json`,
           que es el paquete ejecutable por CuyScout.

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
        | `CUYSCOUT_DRIVER_ID` | `ios-simulator` | Usa `ios-device` para crear la prueba en un iPhone físico |
        | `CUYSCOUT_DEVICE_ID` | vacío | UDID del iPhone físico elegido |
        | `CUYSCOUT_APP_PATH` | vacío | Instalador firmado para iPhone (`.app` o `.ipa`) |
        | `CUYSCOUT_DEVELOPMENT_TEAM` | vacío | Equipo Apple que firma el runner físico |
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
        # Un agente corre esto UNA vez, antes de abrir cualquier sesión de prueba.
        set -euo pipefail
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cuyscout-connection.sh"

        CUYSCOUT_REPO="${CUYSCOUT_REPO:-\#(options.cuyscoutRepoPath)}"
        CUYSCOUT_PORT="${CUYSCOUT_PORT:-\#(options.port)}"
        CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        LOG_FILE="${CUYSCOUT_LOG:-/tmp/cuyscout-gateway.log}"
        MAX_WAIT_SECONDS="${CUYSCOUT_BOOT_TIMEOUT:-60}"

        is_up() {
          curl -sf "${CUYSCOUT_URL}/status" >/dev/null 2>&1
        }

        if is_up; then
          echo "CuyScout ya está arriba en ${CUYSCOUT_URL}"
          exit 0
        fi

        if [[ "${CUYSCOUT_URL}" != http://127.0.0.1:* && "${CUYSCOUT_URL}" != http://localhost:* ]]; then
          echo "El gateway compartido no responde en ${CUYSCOUT_URL}. Abre CuyScout.app y pulsa Iniciar gateway; no se iniciará otro servidor para evitar sesiones duplicadas." >&2
          exit 1
        fi

        CUYSCOUT_BIN="${CUYSCOUT_BIN:-}"
        INSTALLED_BIN="/Applications/CuyScout.app/Contents/MacOS/cuyscout"
        if [[ -n "${CUYSCOUT_BIN}" && -x "${CUYSCOUT_BIN}" ]]; then
          echo "Levantando CuyScout desde ${CUYSCOUT_BIN} ..."
          nohup "${CUYSCOUT_BIN}" "${CUYSCOUT_PORT}" >"${LOG_FILE}" 2>&1 &
          echo $! > /tmp/cuyscout-gateway.pid
        elif [[ -n "${CUYSCOUT_REPO}" && -f "${CUYSCOUT_REPO}/Package.swift" ]]; then
          echo "Levantando CuyScout desde ${CUYSCOUT_REPO} ..."
          (
            cd "${CUYSCOUT_REPO}"
            nohup swift run cuyscout "${CUYSCOUT_PORT}" >"${LOG_FILE}" 2>&1 &
            echo $! > /tmp/cuyscout-gateway.pid
          )
        elif [[ -x "${INSTALLED_BIN}" ]]; then
          echo "Levantando CuyScout desde ${INSTALLED_BIN} ..."
          nohup "${INSTALLED_BIN}" "${CUYSCOUT_PORT}" >"${LOG_FILE}" 2>&1 &
          echo $! > /tmp/cuyscout-gateway.pid
        else
          echo "No se encontró CuyScout.app ni el repo. Ajusta CUYSCOUT_BIN o CUYSCOUT_REPO." >&2
          exit 1
        fi

        echo "Esperando a que ${CUYSCOUT_URL}/status responda (timeout ${MAX_WAIT_SECONDS}s, log en ${LOG_FILE}) ..."
        elapsed=0
        until is_up; do
          if (( elapsed >= MAX_WAIT_SECONDS )); then
            echo "CuyScout no arrancó a tiempo. Revisa ${LOG_FILE}." >&2
            exit 1
          fi
          sleep 2
          elapsed=$((elapsed + 2))
        done

        echo "CuyScout arriba en ${CUYSCOUT_URL} (pid $(cat /tmp/cuyscout-gateway.pid 2>/dev/null || echo '?'))"

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
        source "${SCRIPT_DIR}/cuyscout-connection.sh"
        CUYSCOUT_PORT="${CUYSCOUT_PORT:-\#(options.port)}"
        CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        DRIVER_ID="${CUYSCOUT_DRIVER_ID:-ios-simulator}"
        DEVICE_ID="${CUYSCOUT_DEVICE_ID:-}"
        PROJECT_APP_PATH=""
        if [[ -f "${PROJECT_DIR}/.cuyscout-project.json" ]]; then
          PROJECT_APP_PATH="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("physical" if sys.argv[2]=="ios-device" else "simulator", ""))' "${PROJECT_DIR}/.cuyscout-project.json" "${DRIVER_ID}")"
        fi
        APP_PATH="${1:-${CUYSCOUT_APP_PATH:-${PROJECT_APP_PATH:-${\#(options.envPrefix)_APP_PATH:-\#(options.appPath)}}}}"
        if [[ "${DRIVER_ID}" == "ios-device" && -z "${1:-}" && -z "${CUYSCOUT_APP_PATH:-}" && -z "${PROJECT_APP_PATH}" ]]; then
          echo "Falta instalador firmado para iPhone. Elígelo en CuyScout.app o define CUYSCOUT_APP_PATH." >&2
          exit 1
        fi
        scout_curl() {
          if [[ -n "${CUYSCOUT_TOKEN:-}" ]]; then curl -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "$@"
          else curl "$@"; fi
        }

        if [[ ! -e "${APP_PATH}" ]]; then
          echo "No existe el instalador en ${APP_PATH}. Compílalo o pasa la ruta correcta como \$1." >&2
          exit 1
        fi

        "${SCRIPT_DIR}/ensure-cuyscout.sh" >&2

        SESSION_BODY=$(REPLAY_APP_PATH="${APP_PATH}" REPLAY_DRIVER_ID="${DRIVER_ID}" REPLAY_DEVICE_ID="${DEVICE_ID}" python3 -c '
        import json,os
        caps={"platformName":"iOS","appium:automationName":"XCUITest","appium:driverId":os.environ["REPLAY_DRIVER_ID"],"appium:app":os.environ["REPLAY_APP_PATH"]}
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
        while true; do
          READY=$(scout_curl -sf "${CUYSCOUT_URL}/session/${SESSION}/readiness" | python3 -c '
        import json, sys
        data = json.load(sys.stdin)
        value = data.get("value", data)
        print(value.get("interactionReady", False))
        ')
          [[ "${READY}" == "True" ]] && break
          if (( elapsed >= 180 )); then
            echo "La sesión ${SESSION} no quedó lista a tiempo (xctest_runner_starting persiste)." >&2
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
        # Hook "After" de un Scenario: valida el plan grabado, exporta la prueba
        # reproducible en TypeScript y borra la sesión. Se corre siempre, haya
        # pasado o fallado el escenario.
        set -euo pipefail
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cuyscout-connection.sh"

        SESSION="${1:?Uso: close-session.sh <sessionId> [nombre-escenario]}"
        SCENARIO_NAME="${2:-scenario}"
        CUYSCOUT_PORT="${CUYSCOUT_PORT:-4723}"
        CUYSCOUT_URL="${CUYSCOUT_URL:-http://127.0.0.1:${CUYSCOUT_PORT}}"
        scout_curl() {
          if [[ -n "${CUYSCOUT_TOKEN:-}" ]]; then curl -H "Authorization: Bearer ${CUYSCOUT_TOKEN}" "$@"
          else curl "$@"; fi
        }
        OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/output"
        mkdir -p "${OUT_DIR}"

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

        REPLAY_VALUES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/replay-values"
        mkdir -p "${REPLAY_VALUES_DIR}"
        echo "Guardando valores locales del replay fuera del artefacto ..."
        scout_curl -sf -X POST "${CUYSCOUT_URL}/session/${SESSION}/recording/replay-values" \
          -o "${REPLAY_VALUES_DIR}/${SCENARIO_NAME}.json"
        chmod 600 "${REPLAY_VALUES_DIR}/${SCENARIO_NAME}.json"

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
        if [[ -f "${PROJECT_DIR}/.cuyscout-project.json" ]]; then
          PROJECT_APP_PATH="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("physical" if sys.argv[2]=="physical" else "simulator", ""))' "${PROJECT_DIR}/.cuyscout-project.json" "${RECORDED_KIND}")"
        fi
        APP_PATH="${CUYSCOUT_REPLAY_APP_PATH:-${PROJECT_APP_PATH:-\#(options.appPath)}}"
        if [[ "${RECORDED_KIND}" == "physical" && -z "${CUYSCOUT_REPLAY_APP_PATH:-}" && -z "${PROJECT_APP_PATH}" ]]; then
          echo "Falta instalador firmado para iPhone. Elígelo en CuyScout.app o define CUYSCOUT_REPLAY_APP_PATH." >&2
          exit 1
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
