import Foundation

extension ProjectScaffolder {
    /// Sourced helpers shared by generated scripts. JSON is read as data, never evaluated.
    static let androidProjectSettings = #"""
    #!/usr/bin/env bash
    scout_config() {
      python3 - "$PROJECT_DIR/.cuyscout-project.json" "$1" <<'PY'
    import json, os, sys
    path, key = sys.argv[1:]
    data = json.load(open(path)) if os.path.isfile(path) else {}
    if key == "platform":
        # CUYSCOUT_PLATFORM elige la plataforma de esta ejecución; si no, la del proyecto.
        forced = os.environ.get("CUYSCOUT_PLATFORM", "").strip().lower()
        if forced in ("ios", "android"): print(forced)
        else: print(data.get("platform") or ("android" if data.get("android") and not (data.get("simulator") or data.get("physical") or data.get("physicalBundleId")) else "ios"))
    else:
        for part in key.split("."): data = data.get(part, {}) if isinstance(data, dict) else {}
        print(data if isinstance(data, (str, int)) else "")
    PY
    }
    # Plataformas con instalador o app configurados: "ios", "android" o "ios android".
    scout_platforms() {
      python3 - "$PROJECT_DIR/.cuyscout-project.json" <<'PY'
    import json, os, sys
    data = json.load(open(sys.argv[1])) if os.path.isfile(sys.argv[1]) else {}
    found = []
    if data.get("simulator") or data.get("physical") or data.get("physicalBundleId"): found.append("ios")
    if (data.get("android") or {}).get("applicationId"): found.append("android")
    print(" ".join(found or ["ios"]))
    PY
    }
    # Falla con un mensaje claro si la plataforma pedida no está configurada en el proyecto.
    scout_require_platform() {
      local platform platforms
      platform="$(scout_config platform)"; platforms="$(scout_platforms)"
      case " ${platforms} " in *" ${platform} "*) return 0 ;; esac
      echo "Este proyecto no tiene ${platform} configurado (tiene: ${platforms}). Añádelo con: cuyscout init \"$PROJECT_DIR\" --platform ${platform} ..." >&2
      return 1
    }
    scout_multi_platform() { [[ "$(scout_platforms)" == *" "* ]]; }
    # Nombre de los archivos de salida: <escenario>.<plataforma> si el proyecto tiene las dos,
    # <escenario> si solo tiene una (así lo ya grabado sigue valiendo).
    scout_stem() {
      local name="${1%.cuyscout.json}" platform="${2:-$(scout_config platform)}"
      case "$name" in *.ios|*.android) printf '%s\n' "$name"; return ;; esac
      if scout_multi_platform; then printf '%s.%s\n' "$name" "$platform"; else printf '%s\n' "$name"; fi
    }
    # Lo que escribió la persona: un artefacto que existe tal cual gana; si no, el de la plataforma activa.
    scout_resolve_stem() {
      local name="${1%.cuyscout.json}"
      if [[ -f "$PROJECT_DIR/output/$name.cuyscout.json" ]]; then printf '%s\n' "$name"; return; fi
      scout_stem "$name"
    }
    # Valores del replay: los del escenario con plataforma o, si no hay, los del escenario base.
    scout_values_file() {
      local stem="$1" dir="$PROJECT_DIR/fixtures/replay-values" base="${1%.ios}"
      base="${base%.android}"
      if [[ ! -f "$dir/$stem.json" && -f "$dir/$base.json" ]]; then printf '%s\n' "$dir/$base.json"; else printf '%s\n' "$dir/$stem.json"; fi
    }
    scout_adb() {
      local candidate
      for candidate in "${ANDROID_HOME:-}/platform-tools/adb" "${ANDROID_SDK_ROOT:-}/platform-tools/adb" "$(command -v adb || true)" "${HOME}/Library/Android/sdk/platform-tools/adb"; do
        if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return; fi
      done
      echo "Falta adb; instala platform-tools y configura ANDROID_HOME o PATH." >&2
      return 1
    }
    # Appium exige ANDROID_HOME/ANDROID_SDK_ROOT. Si no están (p. ej. adb de Homebrew o app lanzada
    # desde Finder), se deduce la raíz del SDK desde el adb elegido: <raíz>/platform-tools/adb.
    scout_export_sdk_root() {
      local adb="$1" real root
      if [[ -n "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then export ANDROID_SDK_ROOT="$ANDROID_HOME"; fi
      if [[ -n "${ANDROID_SDK_ROOT:-}" && -z "${ANDROID_HOME:-}" ]]; then export ANDROID_HOME="$ANDROID_SDK_ROOT"; fi
      [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]] && return 0
      real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$adb")"
      root="$(dirname "$(dirname "$real")")"
      if [[ -d "$root/platform-tools" ]]; then export ANDROID_HOME="$root" ANDROID_SDK_ROOT="$root"; fi
    }
    # Actividad principal (la que abre el icono) de una app ya instalada, para apps sin actividad configurada.
    # Con --user 0: un teléfono con perfil de trabajo tiene más de un usuario y adb shell no puede recorrerlos todos.
    scout_launcher_activity() {
      local adb="$1" serial="$2" package="$3" line
      line="$("$adb" -s "$serial" shell cmd package resolve-activity --user 0 --brief -c android.intent.category.LAUNCHER "$package" 2>/dev/null | tr -d '\r' | tail -1)"
      [[ "$line" == "$package"/* ]] && printf '%s\n' "${line#*/}"
    }
    # Appium replay requires an online device. Opening a gateway session can boot an AVD.
    scout_android_serial() {
      local adb="$1" kind="$2" avd="$3" serial name
      while read -r serial; do
        [[ -n "$serial" ]] || continue
        if [[ "$kind" == "simulator" ]]; then
          [[ "$serial" == emulator-* || "$("$adb" -s "$serial" shell getprop ro.kernel.qemu)" == "1" ]] || continue
          if [[ -n "$avd" ]]; then
            name="$("$adb" -s "$serial" emu avd name | head -1 | tr -d '\r')"
            [[ "$name" == "$avd" ]] || continue
          fi
        else
          [[ "$serial" != emulator-* && "$("$adb" -s "$serial" shell getprop ro.kernel.qemu)" != "1" ]] || continue
        fi
        printf '%s\n' "$serial"; return
      done < <("$adb" devices -l | awk '$2=="device" {print $1}')
      echo "No hay Android online del tipo solicitado. Conecta y autoriza el físico o arranca el AVD; comprueba adb devices -l." >&2
      return 1
    }

    """#

    static func androidAgentsMarkdownBlock(for options: Options) -> String {
        let guide = options.cuyscoutRepoPath.isEmpty ? "Consulta GET /help del gateway." : "Lee \(options.cuyscoutRepoPath)/.claude/skills/cuyscout-android/SKILL.md."
        return """
        \(agentsMarkdownStartMarker)
        # Pruebas de \(options.appName) con CuyScout

        Este proyecto prueba una app Android sin su código fuente. \(guide)
        `.cuyscout-project.json` conserva `android.apk`, `applicationId`, actividad y destino.
        `features/`, fixtures y reglas pertenecen al proyecto: no los reemplaces al actualizar.

        ## Conexión y sesión

        \(options.useMCP ? "Usa MCP primero: cuyscout_list_sessions, cuyscout_session_readiness, cuyscout_observe y cuyscout_execute. Si MCP no está disponible, usa el mismo gateway HTTP/curl." : "Usa HTTP/curl con el gateway existente.")
        Carga URL y token con `source scripts/cuyscout-connection.sh`; nunca inventes el token.
        Consulta `/sessions` antes de crear una sesión. Recupera la de este proyecto si existe;
        conserva su ID y comprueba readiness. No repitas una creación de resultado incierto ni
        cierres sesiones ajenas. Una reserva caducada no se reutiliza.

        Si hace falta una sesión nueva: `SESSION=$(scripts/open-session.sh)`. El script selecciona
        android-emulator o android-device y pasa APK/package/actividad y projectDir al gateway.
        \(options.useMCP ? "En MCP usa cuyscout_create_session con platformName Android, bundleIdentifier como package, appActivity opcional, driverId y appPath solo si necesitas instalar el APK." : "En HTTP usa platformName Android, appium:appPackage, appium:appActivity opcional y appium:driverId.")

        ## Conducir la app

        Repite observe → decidir → execute → observe. La lectura normal es
        `/session/$SESSION/observe?maxActions=20`: usa actions para actuar y texts para verificar.
        Ejecuta solo `actions[i].action` con valores resueltos, no la sugerencia completa.
        resource-id/testTag corresponde a accessibilityIdentifier; contentDescription a label.
        No inventes selectores ni coordenadas. No uses predicate de iOS; el runner lo rechaza.
        Los gestos del gateway usan dp. Readiness añade runner_starting y bridgeConnected;
        espera a interactionReady antes de actuar. Usa capturas o árbol completo solo para diagnóstico.

        ## Escenarios y evidencia

        Guarda escenarios en features/*.feature. Para una prueba ya grabada, usa
        `scripts/replay-cuyscout.sh <escenario>` o `scripts/replay-appium.sh <escenario>`.
        preserve mantiene estado, restart reinicia sin borrar datos y reinstall borra los datos.
        No reintentes pagos u otras acciones irreversibles si el resultado es incierto: observa.
        Antes de cerrar, exporta el artefacto y TypeScript/Maestro; `scripts/close-session.sh`
        conserva evidencia. No afirmes que una prueba pasó si no verificaste su resultado.
        Nunca guardes credenciales, tokens o datos personales en reglas, fixtures públicas o logs.
        Conserva los valores sensibles como parámetros de ejecución.

        ## Requisitos Android

        El gateway necesita adb y los APK del runner (Scripts/build_android_runner.sh).
        USB usa adb reverse; Wi-Fi exige bind/URL alcanzables y token. Un físico debe estar
        desbloqueado y autorizado. No requiere firma Apple ni modo iPhone del gateway.
        Appium requiere UiAutomator2; `scripts/replay-appium.sh --check` comprueba dependencias.
        Para replay Appium deja el dispositivo conectado/AVD encendido. Usa
        CUYSCOUT_DRIVER_ID, CUYSCOUT_DEVICE_ID y CUYSCOUT_APP_ACTIVITY para cambiar el destino.
        \(agentsMarkdownEndMarker)
        """ + "\n"
    }
}
