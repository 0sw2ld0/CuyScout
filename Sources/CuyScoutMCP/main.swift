import Foundation
import CuyScoutCore

final class MCPServer {
    private let gateway = ProcessInfo.processInfo.environment["CUYSCOUT_GATEWAY_URL"].map { GatewayClient(address: $0) }
    private let engine = ScoutEngine()
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput

    func run() {
        while let line = readLine() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let data = Data(line.utf8)
            let object: Any
            do { object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
            catch {
                write(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Malformed JSON-RPC input line (invalid JSON, e.g. missing closing brace). This is a transport syntax error, NOT an app or secure-field failure. No action performed; no request sent to gateway. Serialize the entire request with JSON.stringify/json.dumps instead of hand-writing JSON, then send one complete JSON object per line."]])
                continue
            }
            guard let request = object as? [String: Any], request["jsonrpc"] as? String == "2.0", request["method"] is String else {
                write(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Expected a JSON-RPC 2.0 request object with method:string. No action performed."]])
                continue
            }
            var requestID: Any = NSNull()
            do {
                requestID = request["id"] ?? NSNull()
                if request["id"] == nil { continue }
                let response = try handle(request)
                write(response)
            } catch {
                write(["jsonrpc": "2.0", "id": requestID, "error": ["code": -32000, "message": error.localizedDescription]])
            }
        }
    }

    private func handle(_ request: [String: Any]) throws -> [String: Any] {
        let id = request["id"] ?? NSNull(); let method = request["method"] as? String ?? ""
        switch method {
        case "initialize": return ["jsonrpc": "2.0", "id": id, "result": ["protocolVersion": "2024-11-05", "instructions": AgentContract.instructions, "capabilities": ["tools": [:], "resources": ["subscribe": false, "listChanged": false], "prompts": ["listChanged": false]], "serverInfo": ["name": "cuyscout", "version": "0.1.0"]]]
        case "notifications/initialized": return ["jsonrpc": "2.0", "id": id, "result": [:]]
        case "tools/list": return ["jsonrpc": "2.0", "id": id, "result": ["tools": tools().filter { gateway == nil || GatewayClient.supported.contains($0["name"] as? String ?? "") }]]
        case "resources/list": return ["jsonrpc": "2.0", "id": id, "result": ["resources": gateway == nil ? resources() : []]]
        case "resources/templates/list": return ["jsonrpc": "2.0", "id": id, "result": ["resourceTemplates": gateway == nil ? resourceTemplates() : []]]
        case "resources/read":
            guard gateway == nil else { throw ScoutError.unsupported("Gateway mode uses tools only; call cuyscout_help") }
            return try readResource(id: id, params: request["params"] as? [String: Any] ?? [:])
        case "prompts/list": return ["jsonrpc": "2.0", "id": id, "result": ["prompts": prompts()]]
        case "prompts/get":
            if gateway != nil {
                guard (request["params"] as? [String: Any])?["name"] as? String == "cuyscout_explore_to_test" else { throw ScoutError.invalidRequest("Unknown prompt") }
                return ["jsonrpc": "2.0", "id": id, "result": ["messages": [["role": "user", "content": ["type": "text", "text": AgentContract.instructions]]]]]
            }
            return try getPrompt(id: id, params: request["params"] as? [String: Any] ?? [:])
        case "tools/call":
            do { return try callTool(id: id, params: request["params"] as? [String: Any] ?? [:]) }
            catch { return toolResult(id: id, value: ["error": error.localizedDescription, "nextAction": "Use cuyscout_help and inspect readiness/current state. Never automatically retry an irreversible action."], isError: true) }
        default: throw ScoutError.invalidRequest("MCP method not supported: \(method)")
        }
    }

    private func tools() -> [[String: Any]] {
        [
            tool("cuyscout_help", "Start here: complete tool-only workflow, response shapes, executable action example, recovery and export instructions. No files required.", [:]),
            tool("cuyscout_end_session", "Cierra una sesión y libera el runner/dispositivo", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_status", "Comprueba que CuyScout esté disponible", [:]),
            tool("cuyscout_doctor", "Comprueba dependencias de Xcode, simctl, Swift y WebKit", [:]),
            tool("cuyscout_conformance", "Resume capacidades W3C/Appium, limitaciones y validaciones pendientes", [:]),
            tool("cuyscout_record_lesson", "Guarda una lección global, de proyecto o de sesión para futuras exploraciones", ["type": "object", "required": ["scope", "title", "observation", "recommendation"], "properties": ["scope": ["type": "string", "enum": ["global", "project", "session"]], "sessionId": ["type": "string"], "title": ["type": "string"], "observation": ["type": "string"], "recommendation": ["type": "string"], "evidence": ["type": "string"], "tags": ["type": "array", "items": ["type": "string"]], "confidence": ["type": "number"]]]),
            tool("cuyscout_list_lessons", "Busca lecciones compactas por texto o tags; con sessionId combina global, proyecto y sesión", ["type": "object", "properties": ["sessionId": ["type": "string"], "query": ["type": "string"], "tags": ["type": "array", "items": ["type": "string"]], "scope": ["type": "string", "enum": ["global", "project", "session"]], "limit": ["type": "integer"]]]),
            tool("cuyscout_learn_from_session", "Infiere lecciones sin secretos desde fallos, ciclos y latencias de una grabación; puede previsualizarlas o persistirlas", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "scope": ["type": "string", "enum": ["project", "session"]], "persist": ["type": "boolean"]]]),
            tool("cuyscout_drivers", "Lista drivers registrados y su estado de salud", [:]),
            tool("cuyscout_plugins", "Lista plugins cargados y sus capacidades", [:]),
            tool("cuyscout_events", "Obtiene eventos compactos de comandos de una sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "after": ["type": "integer"], "kind": ["type": "string"]]]),
            tool("cuyscout_wait_events", "Espera eventos nuevos en una sola llamada para evitar polling y consumo de tokens", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "after": ["type": "integer"], "kind": ["type": "string"], "timeoutSeconds": ["type": "number"]]]),
            tool("cuyscout_metrics", "Resume comandos, fallos y latencias de una sesión sin leer todos sus eventos", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_fleet_metrics", "Resume salud y rendimiento global del gateway", [:]),
            tool("cuyscout_export_artifacts", "Exporta un paquete JSON versionado con sesión, eventos, métricas, checkpoints y plan", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_list_artifacts", "Lista artefactos persistidos localmente", [:]),
            tool("cuyscout_artifact_catalog", "Lista metadatos compactos para elegir un artefacto restaurable sin descargarlo completo", [:]),
            tool("cuyscout_artifact_status", "Resume disponibilidad, cantidad persistida y frecuencia de autosave", [:]),
            tool("cuyscout_security_audit", "Lista decisiones de seguridad permitidas o bloqueadas de una sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "limit": ["type": "integer"]]]),
            tool("cuyscout_restore_persisted_artifact", "Restaura un artefacto persistido por su ID", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_restore_artifacts", "Restaura una sesión desde un paquete JSON si su dispositivo sigue disponible", ["type": "object", "required": ["artifact"], "properties": ["artifact": ["type": "object"]]]),
            tool("cuyscout_validate_restore", "Valida un artefacto antes de restaurarlo y evita reservar dispositivos con datos incompatibles", ["type": "object", "required": ["artifact"], "properties": ["artifact": ["type": "object"]]]),
            tool("cuyscout_scheduler", "Muestra leases de dispositivos por sesión", [:]),
            tool("cuyscout_heartbeat", "Renueva explícitamente el lease mientras el agente analiza o espera", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_list_devices", "Lista simuladores iOS disponibles", [:]),
            tool("cuyscout_install_app", "Instala un .app en el simulador de la sesión", ["type": "object", "required": ["sessionId", "appPath"], "properties": ["sessionId": ["type": "string"], "appPath": ["type": "string"]]]),
            tool("cuyscout_remove_app", "Desinstala una app del simulador", ["type": "object", "required": ["sessionId", "bundleId"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"]]]),
            tool("cuyscout_reset_app", "Desinstala y vuelve a lanzar una app para iniciar limpia", ["type": "object", "required": ["sessionId", "bundleId"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"]]]),
            tool("cuyscout_activate_app", "Lanza o reactiva la app de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"]]]),
            tool("cuyscout_terminate_app", "Termina la app de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"]]]),
            tool("cuyscout_background_app", "Envía la app al background durante un tiempo opcional", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "seconds": ["type": "number"]]]),
            tool("cuyscout_create_session", "Crea una sesión para un dispositivo usando un driver registrado", ["type": "object", "properties": ["deviceId": ["type": "string"], "bundleIdentifier": ["type": "string"], "driverId": ["type": "string"], "waitSeconds": ["type": "number"]]]),
            tool("cuyscout_session_capabilities", "Devuelve capabilities W3C/Appium compactas y el puerto asignado a la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_device_info", "Devuelve información compacta del dispositivo de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_device_time", "Devuelve la hora observada por CuyScout para sincronizar diagnósticos", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_find_element_from_element", "Busca un descendiente desde una referencia W3C; soporta Native (XCTest) y WebView CSS", ["type": "object", "required": ["sessionId", "parentElementId", "value"], "properties": ["sessionId": ["type": "string"], "parentElementId": ["type": "string"], "strategy": ["type": "string"], "value": ["type": "string"]]]),
            tool("cuyscout_find_elements_from_element", "Busca descendientes desde una referencia W3C; soporta Native (XCTest) y WebView CSS", ["type": "object", "required": ["sessionId", "parentElementId", "value"], "properties": ["sessionId": ["type": "string"], "parentElementId": ["type": "string"], "strategy": ["type": "string"], "value": ["type": "string"]]]),
            tool("cuyscout_execute", "Ejecuta una acción de control o consulta", ["type": "object", "required": ["sessionId", "action"], "properties": ["sessionId": ["type": "string"], "action": ["type": "object"]]]),
            tool("cuyscout_execute_resilient", "Ejecuta una acción y repara automáticamente un selector roto si encuentra una alternativa confiable", ["type": "object", "required": ["sessionId", "action"], "properties": ["sessionId": ["type": "string"], "action": ["type": "object"]]]),
            tool("cuyscout_execute_batch", "Ejecuta varias acciones; requestId evita duplicados, timeoutSeconds limita la duración y retryInfrastructure reintenta solo fallos de infraestructura", ["type": "object", "required": ["sessionId", "actions"], "properties": ["sessionId": ["type": "string"], "actions": ["type": "array", "items": ["type": "object"]], "requestId": ["type": "string"], "resilient": ["type": "boolean"], "stopOnError": ["type": "boolean"], "includeResults": ["type": "boolean"], "timeoutSeconds": ["type": "number"], "retryInfrastructure": ["type": "boolean"], "maxRetries": ["type": "integer"]]]),
            tool("cuyscout_batch_summary", "Devuelve un resumen compacto del último batch o de un requestId, con categorías, pasos fallidos y siguiente acción", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "requestId": ["type": "string"]]]),
            tool("cuyscout_cancel_batch", "Solicita cancelar un batch identificado por requestId entre dos acciones", ["type": "object", "required": ["sessionId", "requestId"], "properties": ["sessionId": ["type": "string"], "requestId": ["type": "string"]]]),
            tool("cuyscout_validate_batch", "Valida un batch antes de ejecutarlo y detecta secuencias vacías o placeholders", ["type": "object", "required": ["sessionId", "actions"], "properties": ["sessionId": ["type": "string"], "actions": ["type": "array", "items": ["type": "object"]]]]),
            tool("cuyscout_accessibility_tree", "ÚLTIMO RECURSO: árbol de accesibilidad crudo, entre 7 y 12 veces más caro que cuyscout_observe y compuesto sobre todo por geometría y contenedores anónimos no accionables. Usa cuyscout_observe salvo que necesites un dato concreto que la observación no trajo", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "visibleOnly": ["type": "boolean"], "interactiveOnly": ["type": "boolean"], "maxElements": ["type": "integer"]]]),
            tool("cuyscout_page_info", "Devuelve contexto, URL, título y tamaño de la fuente sin descargar el DOM completo", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_action_suggestions", "Propone acciones compactas a partir de controles visibles para acelerar la exploración", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "maxSuggestions": ["type": "integer"]]]),
            tool("cuyscout_available_actions", "Solo los controles accionables, sin textos ni estado. Prefiere cuyscout_observe, que trae esto y además los textos de la pantalla por un coste casi idéntico", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "maxActions": ["type": "integer"]]]),
            tool("cuyscout_observe", "LEE LA PANTALLA. Úsala en cada vuelta del bucle: devuelve los controles accionables (actions, con selector semántico) y los textos visibles (texts, para verificar importes, códigos y mensajes), más stateId y si la pantalla cambió. Es la lectura normal y cuesta ~300 tokens; no descargues el árbol de accesibilidad completo para esto", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "maxActions": ["type": "integer"]]]),
            tool("cuyscout_agent_state", "Observación completa más contexto de decisión: métricas, últimos errores, bloqueos, aviso de bucle (loopDetected) y lecciones aprendidas en sesiones anteriores sobre esta app. Úsala cuando algo falla o no avanza; lightweight evita leer la pantalla", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "maxActions": ["type": "integer"], "recentEvents": ["type": "integer"], "lightweight": ["type": "boolean"]]]),
            tool("cuyscout_session_readiness", "Comprueba si la sesión ya puede interactuar, sin leer la pantalla (~40 tokens). Espera aquí tras crear la sesión mientras reporte el bloqueo xctest_runner_starting, en vez de reintentar acciones", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_session_health", "Resume readiness, bloqueos, presupuesto y fallos de una sesión en una llamada", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_get_timeouts", "Consulta los timeouts W3C de una sesión en milisegundos", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_set_timeouts", "Configura timeouts W3C implicit, pageLoad y script en milisegundos", ["type": "object", "required": ["sessionId", "timeouts"], "properties": ["sessionId": ["type": "string"], "timeouts": ["type": "object"]]]),
            tool("cuyscout_window_rect", "Obtiene el rectángulo de la ventana activa (x, y, width, height)", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_set_window_rect", "Configura el rectángulo de la ventana activa (solo WebView)", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "x": ["type": "number"], "y": ["type": "number"], "width": ["type": "number"], "height": ["type": "number"]]]),
            tool("cuyscout_element_selected", "Indica si un elemento referenciado está seleccionado", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"]]]),
            tool("cuyscout_element_name", "Obtiene el nombre accesible de un elemento referenciado", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"]]]),
            tool("cuyscout_element_property", "Obtiene una propiedad W3C de un elemento referenciado", ["type": "object", "required": ["sessionId", "elementId", "name"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"], "name": ["type": "string"]]]),
            tool("cuyscout_active_element", "Obtiene el elemento activo de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_set_alert_text", "Envía texto a una alerta con campo de entrada", ["type": "object", "required": ["sessionId", "text"], "properties": ["sessionId": ["type": "string"], "text": ["type": "string"]]]),
            tool("cuyscout_get_cookies", "Lista las cookies del contexto WebView activo", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_add_cookie", "Añade una cookie al contexto WebView activo", ["type": "object", "required": ["sessionId", "cookie"], "properties": ["sessionId": ["type": "string"], "cookie": ["type": "object"]]]),
            tool("cuyscout_delete_cookie", "Elimina una cookie por nombre del contexto WebView", ["type": "object", "required": ["sessionId", "name"], "properties": ["sessionId": ["type": "string"], "name": ["type": "string"]]]),
            tool("cuyscout_delete_all_cookies", "Elimina todas las cookies del contexto WebView", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_scroll", "Realiza scroll con desplazamiento x,y", ["type": "object", "required": ["sessionId", "x", "y"], "properties": ["sessionId": ["type": "string"], "x": ["type": "number"], "y": ["type": "number"]]]),
            tool("cuyscout_grant_permission", "Concede un permiso a la app mediante simctl privacy", ["type": "object", "required": ["sessionId", "bundleId", "service"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"], "service": ["type": "string", "enum": ["camera", "contacts", "location", "photos", "microphone", "notifications", "calendar", "health"]]]]),
            tool("cuyscout_set_biometry", "Configura la biometría simulada del simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "enrolled": ["type": "boolean"], "enabled": ["type": "boolean"]]]),
            tool("cuyscout_set_location", "Establece la ubicación simulada del simulador", ["type": "object", "required": ["sessionId", "latitude", "longitude"], "properties": ["sessionId": ["type": "string"], "latitude": ["type": "number"], "longitude": ["type": "number"]]]),
            tool("cuyscout_visual_diff", "Compara el screenshot actual con el baseline y devuelve diferencia con tolerancia", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "tolerance": ["type": "number"]]]),
            tool("cuyscout_timeline", "Devuelve la línea de tiempo de acciones de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "screenshots": ["type": "boolean"]]]),
            tool("cuyscout_enqueue_session", "Encola una sesión con prioridad para asignación diferida de dispositivo", ["type": "object", "required": [], "properties": ["deviceId": ["type": "string"], "bundleIdentifier": ["type": "string"], "driverId": ["type": "string"], "priority": ["type": "string", "enum": ["low", "normal", "high", "urgent"]]]]),
            tool("cuyscout_session_queue", "Lista las sesiones en cola esperando un dispositivo", ["type": "object", "required": [], "properties": [:]]),
            tool("cuyscout_cancel_queued_session", "Cancela una sesión encolada por ID", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_fleet_dashboard", "Devuelve un resumen agregado de dispositivos, sesiones, cola, workers y salud", ["type": "object", "required": [], "properties": [:]]),
            tool("cuyscout_register_worker", "Registra un worker remoto de device farm con capabilities y capacidad máxima", ["type": "object", "required": ["url"], "properties": ["url": ["type": "string"], "capabilities": ["type": "array", "items": ["type": "string"]], "maxSessions": ["type": "integer"]]]),
            tool("cuyscout_list_workers", "Lista workers remotos registrados con estado online/expired y capacidad", [:]),
            tool("cuyscout_worker_heartbeat", "Renueva el TTL de un worker y actualiza sus sesiones activas", ["type": "object", "required": ["workerId"], "properties": ["workerId": ["type": "string"], "activeSessions": ["type": "integer"]]]),
            tool("cuyscout_cache_app", "Cachéa una ruta de app para instalación rápida", ["type": "object", "required": ["bundleId", "path"], "properties": ["bundleId": ["type": "string"], "path": ["type": "string"]]]),
            tool("cuyscout_app_cache_list", "Lista las apps en caché", ["type": "object", "required": [], "properties": [:]]),
            tool("cuyscout_clear_app_cache", "Elimina una o todas las apps del caché", ["type": "object", "required": [], "properties": ["bundleId": ["type": "string"]]]),
            tool("cuyscout_console_logs", "Lista los logs de consola de una sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "after": ["type": "integer"]]]),
            tool("cuyscout_record_console_log", "Registra un log de consola en la sesión", ["type": "object", "required": ["sessionId", "message"], "properties": ["sessionId": ["type": "string"], "level": ["type": "string"], "message": ["type": "string"], "source": ["type": "string"]]]),
            tool("cuyscout_add_reactive_rule", "Añade una regla reactiva que ejecuta una acción cuando ocurre un evento", ["type": "object", "required": ["sessionId", "rule"], "properties": ["sessionId": ["type": "string"], "rule": ["type": "object"]]]),
            tool("cuyscout_reactive_rules", "Lista las reglas reactivas de una sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_remove_reactive_rule", "Elimina una regla reactiva por ID", ["type": "object", "required": ["sessionId", "ruleId"], "properties": ["sessionId": ["type": "string"], "ruleId": ["type": "string"]]]),
            tool("cuyscout_record_fingerprint", "Registra un fingerprint semántico de elemento para autocuración", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"], "identifier": ["type": "string"], "label": ["type": "string"], "type": ["type": "string"], "frame": ["type": "object"]]]),
            tool("cuyscout_fingerprints", "Lista los fingerprints semánticos registrados para autocuración", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_match_fingerprint", "Busca un fingerprint por identifier, label o tipo para reparar selectores", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "identifier": ["type": "string"], "label": ["type": "string"], "type": ["type": "string"]]]),
            tool("cuyscout_compare_behavior", "Compara el comportamiento esperado con el observado", ["type": "object", "required": ["sessionId", "expectedSuccess", "actualSuccess"], "properties": ["sessionId": ["type": "string"], "expectedSuccess": ["type": "boolean"], "actualSuccess": ["type": "boolean"], "expectedError": ["type": "string"]]]),
            tool("cuyscout_driver_manifests", "Lista los manifests de drivers registrados para carga dinámica", ["type": "object", "required": [], "properties": [:]]),
            tool("cuyscout_register_driver_manifest", "Registra un manifest de driver para carga dinámica", ["type": "object", "required": ["manifest"], "properties": ["manifest": ["type": "object"]]]),
            tool("cuyscout_load_driver", "Carga un driver desde su manifest (Bundle.load)", ["type": "object", "required": ["manifest"], "properties": ["manifest": ["type": "object"]]]),
            tool("cuyscout_plugin_routes", "Lista las rutas HTTP personalizadas registradas por plugins", ["type": "object", "required": [], "properties": [:]]),
            tool("cuyscout_record_network_request", "Registra una solicitud de red en la sesión", ["type": "object", "required": ["sessionId", "method", "url"], "properties": ["sessionId": ["type": "string"], "method": ["type": "string"], "url": ["type": "string"], "status": ["type": "integer"], "requestSize": ["type": "integer"], "responseSize": ["type": "integer"], "durationMilliseconds": ["type": "integer"]]]),
            tool("cuyscout_network_requests", "Lista las solicitudes de red registradas en la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "after": ["type": "integer"]]]),
            tool("cuyscout_set_shard", "Configura sharding para ejecución paralela de pruebas", ["type": "object", "required": ["sessionId", "shardIndex", "shardCount"], "properties": ["sessionId": ["type": "string"], "shardIndex": ["type": "integer"], "shardCount": ["type": "integer"]]]),
            tool("cuyscout_get_shard", "Consulta la configuración de sharding de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_record_otel_span", "Registra un span de OpenTelemetry en la sesión", ["type": "object", "required": ["sessionId", "span"], "properties": ["sessionId": ["type": "string"], "span": ["type": "object"]]]),
            tool("cuyscout_otel_spans", "Lista los spans de OpenTelemetry de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_set_appearance", "Cambia el modo de apariencia del simulador (light o dark)", ["type": "object", "required": ["sessionId", "mode"], "properties": ["sessionId": ["type": "string"], "mode": ["type": "string", "enum": ["light", "dark"]]]]),
            tool("cuyscout_set_status_bar", "Configura la barra de estado del simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "time": ["type": "string"], "dataNetwork": ["type": "string"], "wifiMode": ["type": "string"], "batteryLevel": ["type": "integer"], "batteryState": ["type": "string"]]]),
            tool("cuyscout_start_video_recording", "Inicia grabación de video del simulador", ["type": "object", "required": ["sessionId", "path"], "properties": ["sessionId": ["type": "string"], "path": ["type": "string"]]]),
            tool("cuyscout_stop_video_recording", "Detiene la grabación de video", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_list_apps", "Lista las apps instaladas en el simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_reset_keychain", "Reinicia el keychain del simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_deep_link", "Abre un deep link en la app", ["type": "object", "required": ["sessionId", "url"], "properties": ["sessionId": ["type": "string"], "url": ["type": "string"]]]),
            tool("cuyscout_push_notification", "Envía una push notification al simulador via simctl push", ["type": "object", "required": ["sessionId", "bundleId", "payloadPath"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"], "payloadPath": ["type": "string"]]]),
            tool("cuyscout_set_content_size", "Cambia el tamaño de contenido del simulador", ["type": "object", "required": ["sessionId", "size"], "properties": ["sessionId": ["type": "string"], "size": ["type": "string"]]]),
            tool("cuyscout_add_media", "Añade fotos o videos a la biblioteca del simulador", ["type": "object", "required": ["sessionId", "path"], "properties": ["sessionId": ["type": "string"], "path": ["type": "string"]]]),
            tool("cuyscout_spawn", "Ejecuta un proceso en el simulador via simctl spawn", ["type": "object", "required": ["sessionId", "bundleId"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"], "args": ["type": "array", "items": ["type": "string"]]]]),
            tool("cuyscout_icloud_sync", "Dispara sincronización de iCloud en el simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_element_location", "Obtiene la ubicación y centro de un elemento referenciado", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"]]]),
            tool("cuyscout_element_size", "Obtiene el tamaño de un elemento referenciado", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"]]]),
            tool("cuyscout_shake", "Agita el simulador via simctl ui shake", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_get_appearance", "Consulta el modo de apariencia actual del simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_get_content_size", "Consulta el tamaño de contenido actual del simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_enumerate_files", "Lista archivos del simulador via simctl io enumerate", ["type": "object", "required": ["sessionId", "path"], "properties": ["sessionId": ["type": "string"], "path": ["type": "string"]]]),
            tool("cuyscout_double_tap", "Doble tap sobre un elemento referenciado", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"]]]),
            tool("cuyscout_long_press", "Pulsación larga sobre un elemento referenciado", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"], "duration": ["type": "number"]]]),
            tool("cuyscout_pinch", "Pinch/zoom sobre un elemento referenciado", ["type": "object", "required": ["sessionId", "elementId"], "properties": ["sessionId": ["type": "string"], "elementId": ["type": "string"], "scale": ["type": "number"], "velocity": ["type": "number"]]]),
            tool("cuyscout_boot_device", "Inicia un simulador via simctl boot", ["type": "object", "required": ["deviceId"], "properties": ["deviceId": ["type": "string"]]]),
            tool("cuyscout_shutdown_device", "Apaga un simulador via simctl shutdown", ["type": "object", "required": ["deviceId"], "properties": ["deviceId": ["type": "string"]]]),
            tool("cuyscout_erase_device", "Borra y reinicia un simulador via simctl erase", ["type": "object", "required": ["deviceId"], "properties": ["deviceId": ["type": "string"]]]),
            tool("cuyscout_clone_device", "Clona un simulador via simctl clone", ["type": "object", "required": ["deviceId", "name"], "properties": ["deviceId": ["type": "string"], "name": ["type": "string"]]]),
            tool("cuyscout_delete_device", "Elimina un simulador via simctl delete", ["type": "object", "required": ["deviceId"], "properties": ["deviceId": ["type": "string"]]]),
            tool("cuyscout_create_device", "Crea un simulador via simctl create", ["type": "object", "required": ["name", "runtime"], "properties": ["name": ["type": "string"], "runtime": ["type": "string"]]]),
            tool("cuyscout_rename_device", "Renombra un simulador via simctl rename", ["type": "object", "required": ["deviceId", "name"], "properties": ["deviceId": ["type": "string"], "name": ["type": "string"]]]),
            tool("cuyscout_pbsync", "Sincroniza la biblioteca de fotos del simulador", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_download_file", "Descarga un archivo del simulador al host", ["type": "object", "required": ["sessionId", "source", "destination"], "properties": ["sessionId": ["type": "string"], "source": ["type": "string"], "destination": ["type": "string"]]]),
            tool("cuyscout_upload_file", "Sube un archivo del host al simulador", ["type": "object", "required": ["sessionId", "source", "destination"], "properties": ["sessionId": ["type": "string"], "source": ["type": "string"], "destination": ["type": "string"]]]),
            tool("cuyscout_get_app_container", "Obtiene la ruta del contenedor de una app", ["type": "object", "required": ["sessionId", "bundleId"], "properties": ["sessionId": ["type": "string"], "bundleId": ["type": "string"], "container": ["type": "string"]]]),
            tool("cuyscout_get_config", "Consulta una configuración del simulador", ["type": "object", "required": ["sessionId", "key"], "properties": ["sessionId": ["type": "string"], "key": ["type": "string"]]]),
            tool("cuyscout_set_config", "Configura un valor del simulador", ["type": "object", "required": ["sessionId", "key", "value"], "properties": ["sessionId": ["type": "string"], "key": ["type": "string"], "value": ["type": "string"]]]),
            tool("cuyscout_verify_test_plan", "Verifica el plan de pruebas compilando y ejecutando desde estado limpio", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "format": ["type": "string"], "resetApp": ["type": "boolean"]]]),
            tool("cuyscout_accessibility_overlay", "Genera un overlay de accesibilidad sobre el screenshot actual", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_visual_compare_region", "Compara una región del screenshot actual con el baseline", ["type": "object", "required": ["sessionId", "x", "y", "width", "height"], "properties": ["sessionId": ["type": "string"], "x": ["type": "number"], "y": ["type": "number"], "width": ["type": "number"], "height": ["type": "number"], "tolerance": ["type": "number"]]]),
            tool("cuyscout_set_plugin_security_policy", "Configura la política de seguridad de plugins", ["type": "object", "required": ["policy"], "properties": ["policy": ["type": "object"]]]),
            tool("cuyscout_detect_cycles", "Detecta ciclos en el grafo de navegación mediante DFS", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_ocr", "Reconoce texto en el screenshot actual via Vision framework", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "x": ["type": "number"], "y": ["type": "number"], "width": ["type": "number"], "height": ["type": "number"]]]),
            tool("cuyscout_build_runner", "Compila y firma el runner XCTest via xcodebuild", ["type": "object", "required": ["projectPath", "scheme", "destination"], "properties": ["projectPath": ["type": "string"], "scheme": ["type": "string"], "destination": ["type": "string"], "signingIdentity": ["type": "string"]]]),
            tool("cuyscout_navigation_graph", "Obtiene los estados y transiciones descubiertos", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_exploration_coverage", "Resume estados, transiciones repetidas y riesgo de bucle sin descargar el grafo completo", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_generate_screen_contract", "Genera un contrato versionado de los elementos accesibles de la pantalla actual", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "name": ["type": "string"]]]),
            tool("cuyscout_compare_screen_contract", "Compara la pantalla actual contra un contrato y devuelve elementos faltantes, cambiados e inesperados", ["type": "object", "required": ["sessionId", "contract"], "properties": ["sessionId": ["type": "string"], "contract": ["type": "object"]]]),
            tool("cuyscout_create_checkpoint", "Guarda un checkpoint lógico de la exploración", ["type": "object", "required": ["sessionId", "name"], "properties": ["sessionId": ["type": "string"], "name": ["type": "string"]]]),
            tool("cuyscout_list_checkpoints", "Lista checkpoints guardados para la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_restore_checkpoint", "Reproduce pasos hasta un checkpoint, opcionalmente reiniciando la app", ["type": "object", "required": ["sessionId", "checkpointId"], "properties": ["sessionId": ["type": "string"], "checkpointId": ["type": "string"], "resetApp": ["type": "boolean"]]]),
            tool("cuyscout_accept_alert", "Acepta la alerta del sistema visible", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_dismiss_alert", "Descarta la alerta del sistema visible", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_get_alert_text", "Lee el texto y botones de la alerta visible sin descargar el árbol completo", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_get_contexts", "Lista los contextos nativos y WebView de una sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_webview_status", "Comprueba si el adaptador WebView está conectado", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_register_webview", "Registra contextos publicados por un adaptador WebKit", ["type": "object", "required": ["sessionId", "contexts"], "properties": ["sessionId": ["type": "string"], "contexts": ["type": "array", "items": ["type": "string"]]]]),
            tool("cuyscout_poll_webview", "Obtiene el siguiente script pendiente para el adaptador WebView", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_complete_webview", "Entrega el resultado de un script ejecutado por el adaptador WebView", ["type": "object", "required": ["sessionId", "commandID", "success"], "properties": ["sessionId": ["type": "string"], "commandID": ["type": "string"], "success": ["type": "boolean"], "valueJSON": ["type": "string"], "error": ["type": "string"]]]),
            tool("cuyscout_set_context", "Cambia el contexto activo de una sesión", ["type": "object", "required": ["sessionId", "context"], "properties": ["sessionId": ["type": "string"], "context": ["type": "string"]]]),
            tool("cuyscout_execute_script", "Ejecuta JavaScript en el contexto WebView activo", ["type": "object", "required": ["sessionId", "script"], "properties": ["sessionId": ["type": "string"], "script": ["type": "string"], "args": ["type": "array"]]]),
            tool("cuyscout_register_xctest", "Registra el runner XCTest para permitir tap, swipe, type y accesibilidad", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_xctest_status", "Comprueba conexión, actividad y comandos pendientes del runner XCTest", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_poll_xctest", "Obtiene la siguiente orden pendiente para el runner XCTest", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_start_recording", "NO HACE FALTA: cada sesión se graba desde que se crea y su artefacto se persiste al borrarla. Úsala solo para reiniciar la grabación y descartar los pasos ya grabados", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_stop_recording", "Detiene la grabación y genera un test XCTest", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_get_recording", "Obtiene la grabación actual sin detenerla", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]]),
            tool("cuyscout_get_test_plan", "Obtiene el plan intermedio normalizado antes de exportar código", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_validate_test_plan", "Valida si el plan puede exportarse y ejecutarse", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_get_optimized_test_plan", "Compacta el plan eliminando observaciones y duplicados para ahorrar tokens", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_replay_recording", "Reproduce la grabación sin volver a grabar y devuelve el primer fallo", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "optimized": ["type": "boolean"], "resilient": ["type": "boolean"], "resetApp": ["type": "boolean"], "variables": ["type": "object"]]])
            ,tool("cuyscout_export_replay_junit", "Exporta el resultado del replay en JUnit XML para CI", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "optimized": ["type": "boolean"], "resilient": ["type": "boolean"], "variables": ["type": "object"]]])
            ,tool("cuyscout_repair_selector", "Propone alternativas explicables para un selector que ya no coincide", ["type": "object", "required": ["sessionId", "strategy", "value"], "properties": ["sessionId": ["type": "string"], "strategy": ["type": "string"], "value": ["type": "string"], "limit": ["type": "integer"]]])
            ,tool("cuyscout_preview_repair", "Genera un parche de acción revisable con selector alternativo, score y explicación; no ejecuta ni modifica la prueba", ["type": "object", "required": ["sessionId", "action"], "properties": ["sessionId": ["type": "string"], "action": ["type": "object"], "limit": ["type": "integer"]]])
            ,tool("cuyscout_repair_audit", "Lista o registra la decisión sobre una reparación propuesta para conservar evidencia de autocuración", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "proposal": ["type": "object"], "decision": ["type": "string", "enum": ["proposed", "applied", "rejected"]], "limit": ["type": "integer"]]])
            ,tool("cuyscout_accessibility_audit", "Audita identifiers, labels, tamaños y ambigüedad de controles", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_session_report", "Devuelve un diagnóstico agregado de la sesión y su exploración", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_export_report_html", "Exporta un reporte HTML autocontenido de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_get_security_policy", "Consulta la política de seguridad de la sesión", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_set_security_policy", "Configura restricciones para acciones sensibles", ["type": "object", "required": ["sessionId", "policy"], "properties": ["sessionId": ["type": "string"], "policy": ["type": "object"]]])
            ,tool("cuyscout_start_exploration", "Inicia exploración con límites anti-bucle y grabación automática", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"], "maxActions": ["type": "integer"], "maxStateRepeats": ["type": "integer"], "maxActionRepeats": ["type": "integer"], "timeoutSeconds": ["type": "number"]]])
            ,tool("cuyscout_exploration_status", "Consulta si la exploración está repitiendo estados o acciones", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_stop_exploration", "Finaliza la exploración y devuelve el test generado", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_export_appium", "Exporta la sesión como prueba Appium/WebdriverIO", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_export_appium_typescript", "Exporta la sesión como prueba TypeScript/WebdriverIO", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_export_appium_python", "Exporta la sesión como prueba Appium-Python-Client", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_export_appium_java", "Exporta la sesión como prueba Appium Java/JUnit", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_export_gherkin", "Exporta la sesión como escenario Gherkin legible", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
            ,tool("cuyscout_export_portable", "Exporta los pasos en JSON portable de CuyScout", ["type": "object", "required": ["sessionId"], "properties": ["sessionId": ["type": "string"]]])
        ]
    }

    private func resources() -> [[String: Any]] {
        [["uri": "cuyscout://lessons", "name": "CuyScout lessons", "description": "Lecciones globales compactas para exploraciones", "mimeType": "application/json"]]
    }

    private func resourceTemplates() -> [[String: Any]] {
        [
            ["uriTemplate": "cuyscout://session/{sessionId}/agent-state", "name": "Session agent state", "description": "Estado compacto, readiness, cobertura, hints y lecciones aplicables", "mimeType": "application/json"],
            ["uriTemplate": "cuyscout://session/{sessionId}/lessons", "name": "Session lessons", "description": "Lecciones globales, de proyecto y sesión aplicables", "mimeType": "application/json"],
            ["uriTemplate": "cuyscout://session/{sessionId}/report", "name": "Session report", "description": "Diagnóstico agregado de la sesión", "mimeType": "application/json"],
            ["uriTemplate": "cuyscout://session/{sessionId}/events", "name": "Session events", "description": "Eventos compactos posteriores a un cursor opcional", "mimeType": "application/json"],
            ["uriTemplate": "cuyscout://session/{sessionId}/batch-summary", "name": "Batch summary", "description": "Resumen compacto del último batch o requestId", "mimeType": "application/json"]
        ]
    }

    private func prompts() -> [[String: Any]] {
        [["name": "cuyscout_explore_to_test", "description": "Flujo compacto para explorar una app y convertir la sesión en una prueba validada", "arguments": [["name": "sessionId", "description": "ID de la sesión CuyScout", "required": true], ["name": "goal", "description": "Ruta o comportamiento que se desea cubrir", "required": false]]]]
    }

    private func getPrompt(id: Any, params: [String: Any]) throws -> [String: Any] {
        guard (params["name"] as? String) == "cuyscout_explore_to_test" else { throw ScoutError.invalidRequest("Unknown CuyScout prompt") }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        guard let sessionID = arguments["sessionId"] as? String, !sessionID.isEmpty else { throw ScoutError.invalidRequest("Prompt requires sessionId") }
        let goal = arguments["goal"] as? String ?? "la ruta principal de la aplicación"
        let text = """
Usa CuyScout para explorar \(goal) y producir una prueba reproducible.

1. Lee el recurso cuyscout://session/(sessionID)/agent-state.
2. Consulta cuyscout://session/(sessionID)/lessons y respeta sus hints.
3. Observa y ejecuta solo acciones semánticas; usa límites anti-bucle y checkpoints.
4. Finaliza la exploración y aprende de la sesión.
5. Obtén el plan optimizado y ejecuta cuyscout_validate_test_plan.
6. Si hay selectores rotos, usa cuyscout_preview_repair y registra la decisión antes de aplicar una reparación.
7. Reproduce la prueba desde un estado limpio y exporta Appium Python o TypeScript según el proyecto.

Mantén las respuestas compactas: usa agent-state, diffs, métricas y recursos MCP en lugar de descargar árboles completos repetidamente.
"""
        return ["jsonrpc": "2.0", "id": id, "result": ["description": "Exploración agent-first de CuyScout", "messages": [["role": "user", "content": ["type": "text", "text": text]]]]]
    }

    private func readResource(id: Any, params: [String: Any]) throws -> [String: Any] {
        guard let uri = params["uri"] as? String, let url = URL(string: uri), url.scheme == "cuyscout" else { throw ScoutError.invalidRequest("resources/read requires a cuyscout URI") }
        let value: Any
        if url.host == "lessons" && url.path == "" { value = engine.allLessons(limit: 100) }
        else if url.host == "session" {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2 else { throw ScoutError.invalidRequest("Invalid CuyScout session resource URI") }
            let sessionID = parts[0]
            switch parts[1] {
            case "agent-state": value = try engine.agentState(sessionID: sessionID, maxActions: 10, recentEvents: 5, lightweight: true)
            case "lessons": value = try engine.lessons(sessionID: sessionID, limit: 50)
            case "report": value = try engine.sessionReport(sessionID: sessionID)
            case "events": let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []; let after = Int(query.first(where: { $0.name == "after" })?.value ?? "0") ?? 0; value = try engine.events(sessionID: sessionID, after: after, kind: query.first(where: { $0.name == "kind" })?.value)
            case "batch-summary": let requestID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "requestId" })?.value; value = try engine.batchSummary(sessionID: sessionID, requestID: requestID)
            default: throw ScoutError.invalidRequest("Unknown CuyScout session resource")
            }
        } else { throw ScoutError.invalidRequest("Unknown CuyScout resource") }
        let data = try resourceJSON(value)
        let json = String(data: data, encoding: .utf8) ?? "null"
        return ["jsonrpc": "2.0", "id": id, "result": ["contents": [["uri": uri, "mimeType": "application/json", "text": json]]]]
    }

    private func resourceJSON(_ value: Any) throws -> Data {
        if let lessons = value as? [LearnedLesson] { return try JSONEncoder().encode(lessons) }
        if let state = value as? AgentStateSnapshot { return try JSONEncoder().encode(state) }
        if let report = value as? SessionDiagnosticReport { return try JSONEncoder().encode(report) }
        if let events = value as? [ScoutEvent] { return try JSONEncoder().encode(events) }
        if let summary = value as? BatchCompactSummary { return try JSONEncoder().encode(summary) }
        throw ScoutError.invalidRequest("Unsupported CuyScout resource value")
    }

    private func tool(_ name: String, _ description: String, _ schema: [String: Any]) -> [String: Any] {
        var result: [String: Any] = ["name": name, "description": description, "inputSchema": schema.isEmpty ? ["type": "object", "properties": [:]] : schema]
        let details: [String: String] = [
            "cuyscout_observe": "Payload is {stateId,changed,context,title,texts:string[],actions:[{action:{type,selector,text?},risk,reason}]}. MCP structuredContent is already unwrapped. Copy actions[i].action to cuyscout_execute; do not use actions[i].selector. Never invent IDs. See cuyscout_help.",
            "cuyscout_execute": "Arguments: {sessionId,action: observation.actions[i].action}. Replace <text> for typing. Do not send the risk/reason wrapper. After a timeout observe first; never automatically retry an irreversible action.",
            "cuyscout_session_readiness": "Require interactionReady === true; missing fields are not success. Use blockers to diagnose, keep the existing session.",
            "cuyscout_create_session": "Gateway mode supports appPath (.app/.ipa) and deviceId; returns sessionId. Local mode returns id and requires manual bridge integration. Start with cuyscout_help to inspect mode. Preserve the returned ID; wait for readiness.",
            "cuyscout_export_appium_typescript": "Returns {format,code}. Export BEFORE cuyscout_end_session. Replace <redacted> with runtime variables, add goal assertions and verify compilation/replay separately. Never hardcode an expired session ID.",
            "cuyscout_end_session": "Release the current session in finally, even after assertions fail. Export before closing."
        ]
        if let detail = details[name] { result["description"] = description + ". " + detail }
        if name == "cuyscout_observe" { result["outputSchema"] = AgentContract.observationSchema }
        if name == "cuyscout_execute", var input = result["inputSchema"] as? [String: Any], var properties = input["properties"] as? [String: Any] {
            properties["action"] = ["type": "object", "required": ["type"], "description": "Copy observation.actions[i].action exactly; typeElement requires selector and text. tapElement requires selector.", "properties": ["type": ["type": "string"], "selector": ["type": "object", "required": ["strategy", "value"], "properties": ["strategy": ["type": "string", "enum": ["accessibilityIdentifier", "label", "value", "type", "predicate", "cssSelector", "xpath"]], "value": ["type": "string"]]], "text": ["type": "string"]]]
            input["properties"] = properties; result["inputSchema"] = input
        }
        if name == "cuyscout_create_session", var input = result["inputSchema"] as? [String: Any], var properties = input["properties"] as? [String: Any] {
            properties["appPath"] = ["type": "string", "description": "Installer path on gateway host. Requires CUYSCOUT_GATEWAY_URL mode."]
            input["properties"] = properties; result["inputSchema"] = input
        }
        return result
    }

    private func callTool(id: Any, params: [String: Any]) throws -> [String: Any] {
        let name = params["name"] as? String ?? ""; let args = params["arguments"] as? [String: Any] ?? [:]
        if name == "cuyscout_help" {
            var help = AgentContract.help
            help["mode"] = gateway == nil ? "local-engine-manual-bridge" : "http-gateway"
            help["setup"] = "For installer + automatic runner, start cuyscout on the gateway host and configure this MCP process with CUYSCOUT_GATEWAY_URL=http://127.0.0.1:4723 (or the measured proxy URL). The MCP process needs network access; agents need only MCP tools. Gateway mode advertises only supported tools."
            return toolResult(id: id, value: help)
        }
        if name == "cuyscout_execute" {
            guard let action = args["action"] as? [String: Any], action["type"] is String else { throw ScoutError.invalidRequest("action.type required; copy observe.actions[i].action, not the suggestion wrapper") }
            if let text = action["text"] as? String, ["<text>", "<redacted>"].contains(text) {
                throw ScoutError.invalidRequest("Replace the text placeholder with intended input before executing. No action performed.")
            }
            do {
                _ = try JSONDecoder().decode(ScoutAction.self, from: JSONSerialization.data(withJSONObject: action))
            } catch let error as DecodingError {
                let path: [CodingKey]
                switch error {
                case .keyNotFound(let key, let context): path = context.codingPath + [key]
                case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context): path = context.codingPath
                @unknown default: path = []
                }
                throw ScoutError.invalidRequest("Invalid action at action.\(path.map(\.stringValue).joined(separator: ".")). Copy observe.actions[i].action exactly; typeElement requires selector:{strategy,value} and text:string. Use an advertised selector strategy such as accessibilityIdentifier. No action performed and no request sent to gateway.")
            }
        }
        if let gateway { return toolResult(id: id, value: try gateway.call(name, args: args)) }
        if name == "cuyscout_create_session", args["appPath"] != nil { throw ScoutError.unsupported("appPath requires gateway mode. Configure CUYSCOUT_GATEWAY_URL; see cuyscout_help. No session created.") }
        let value: Any
        switch name {
        case "cuyscout_end_session": try engine.deleteSession(required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_help": value = AgentContract.help
        case "cuyscout_status": value = ["ready": true, "name": "CuyScout"]
        case "cuyscout_doctor": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.doctor()))
        case "cuyscout_conformance": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.conformanceSnapshot()))
        case "cuyscout_record_lesson": let scope = LessonScope(rawValue: try required(args, "scope")) ?? .global; value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.recordLesson(scope: scope, sessionID: args["sessionId"] as? String, title: required(args, "title"), observation: required(args, "observation"), recommendation: required(args, "recommendation"), evidence: args["evidence"] as? String, tags: args["tags"] as? [String] ?? [], confidence: args["confidence"] as? Double ?? 0.8)))
        case "cuyscout_list_lessons": if let sessionID = args["sessionId"] as? String { value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.lessons(sessionID: sessionID, query: args["query"] as? String, tags: args["tags"] as? [String] ?? [], limit: args["limit"] as? Int ?? 10))) } else { value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.allLessons(query: args["query"] as? String, tags: args["tags"] as? [String] ?? [], scope: (args["scope"] as? String).flatMap(LessonScope.init(rawValue:)), limit: args["limit"] as? Int ?? 50))) }
        case "cuyscout_learn_from_session": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.learnFromSession(sessionID: required(args, "sessionId"), scope: (args["scope"] as? String).flatMap(LessonScope.init(rawValue:)) ?? .project, persist: args["persist"] as? Bool ?? true)))
        case "cuyscout_drivers": value = ["drivers": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.drivers())), "health": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.driverHealth()))]
        case "cuyscout_plugins": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.plugins()))
        case "cuyscout_events": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.events(sessionID: required(args, "sessionId"), after: args["after"] as? Int ?? 0, kind: args["kind"] as? String)))
        case "cuyscout_wait_events": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.waitForEvents(sessionID: required(args, "sessionId"), after: args["after"] as? Int ?? 0, timeoutSeconds: args["timeoutSeconds"] as? Double ?? 10, kind: args["kind"] as? String)))
        case "cuyscout_metrics": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.metrics(sessionID: required(args, "sessionId"))))
        case "cuyscout_fleet_metrics": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.fleetMetrics()))
        case "cuyscout_agent_state": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.agentState(sessionID: required(args, "sessionId"), maxActions: args["maxActions"] as? Int ?? 20, recentEvents: args["recentEvents"] as? Int ?? 5, lightweight: args["lightweight"] as? Bool ?? false)))
        case "cuyscout_export_artifacts": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.sessionArtifactBundle(sessionID: required(args, "sessionId"))))
        case "cuyscout_list_artifacts": value = engine.persistedArtifacts()
        case "cuyscout_artifact_catalog": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.artifactCatalog()))
        case "cuyscout_artifact_status": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.artifactStoreStatus()))
        case "cuyscout_security_audit": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.securityAudit(sessionID: required(args, "sessionId"), limit: args["limit"] as? Int ?? 100)))
        case "cuyscout_restore_persisted_artifact": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.restorePersistedArtifact(sessionID: required(args, "sessionId"))))
        case "cuyscout_restore_artifacts": let artifactData = try JSONSerialization.data(withJSONObject: args["artifact"] as? [String: Any] ?? [:]); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.restoreSessionArtifact(artifactData)))
        case "cuyscout_validate_restore": let artifactData = try JSONSerialization.data(withJSONObject: args["artifact"] as? [String: Any] ?? [:]); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.preflightRestore(artifactData)))
        case "cuyscout_scheduler": value = ["leases": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.schedulerLeases()))]
        case "cuyscout_heartbeat": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.heartbeat(sessionID: required(args, "sessionId"))))
        case "cuyscout_list_devices": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.listDevices()))
        case "cuyscout_install_app": try engine.installApp(sessionID: required(args, "sessionId"), path: required(args, "appPath")); value = ["ok": true]
        case "cuyscout_remove_app": try engine.uninstallApp(sessionID: required(args, "sessionId"), bundleIdentifier: required(args, "bundleId")); value = ["ok": true]
        case "cuyscout_reset_app": try engine.resetApp(sessionID: required(args, "sessionId"), bundleIdentifier: required(args, "bundleId")); value = ["ok": true]
        case "cuyscout_activate_app": try engine.activateApp(sessionID: required(args, "sessionId"), bundleIdentifier: args["bundleId"] as? String); value = ["ok": true]
        case "cuyscout_terminate_app": try engine.terminateApp(sessionID: required(args, "sessionId"), bundleIdentifier: args["bundleId"] as? String); value = ["ok": true]
        case "cuyscout_background_app": try engine.backgroundApp(sessionID: required(args, "sessionId"), duration: args["seconds"] as? Double ?? 0); value = ["ok": true]
        case "cuyscout_create_session": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.createSession(deviceID: args["deviceId"] as? String, bundleIdentifier: args["bundleIdentifier"] as? String, driverID: args["driverId"] as? String ?? "ios-simulator", waitSeconds: args["waitSeconds"] as? Double ?? 0)))
        case "cuyscout_session_capabilities": value = try engine.sessionCapabilities(sessionID: required(args, "sessionId"))
        case "cuyscout_device_info": value = try engine.deviceInfo(sessionID: required(args, "sessionId"))
        case "cuyscout_device_time": value = ["value": try engine.deviceTime(sessionID: required(args, "sessionId"))]
        case "cuyscout_find_element_from_element": let strategy = ScoutSelector.Strategy(rawValue: (args["strategy"] as? String) ?? "css selector") ?? .cssSelector; let selector = ScoutSelector(strategy: strategy, value: try required(args, "value")); let elementID = try engine.findElementFromElement(sessionID: required(args, "sessionId"), parentElementID: required(args, "parentElementId"), selector: selector); value = ["elementId": elementID]
        case "cuyscout_find_elements_from_element": let strategy = ScoutSelector.Strategy(rawValue: (args["strategy"] as? String) ?? "css selector") ?? .cssSelector; let selector = ScoutSelector(strategy: strategy, value: try required(args, "value")); value = ["elementIds": try engine.findElementsFromElement(sessionID: required(args, "sessionId"), parentElementID: required(args, "parentElementId"), selector: selector)]
        case "cuyscout_register_xctest": try engine.registerBridge(sessionID: required(args, "sessionId")); value = ["registered": true]
        case "cuyscout_xctest_status": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.bridgeStatus(sessionID: required(args, "sessionId"))))
        case "cuyscout_accessibility_tree":
            let options = AccessibilityOptions(visibleOnly: args["visibleOnly"] as? Bool ?? true, interactiveOnly: args["interactiveOnly"] as? Bool ?? true, maxElements: args["maxElements"] as? Int ?? 40)
            let payload = try engine.perform(.accessibilityTreeWithOptions(options), sessionID: required(args, "sessionId")); value = try payload.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        case "cuyscout_page_info": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.pageInfo(sessionID: required(args, "sessionId"))))
        case "cuyscout_action_suggestions": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.actionSuggestions(sessionID: required(args, "sessionId"), maxSuggestions: args["maxSuggestions"] as? Int ?? 20)))
        case "cuyscout_available_actions": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.actionSuggestions(sessionID: required(args, "sessionId"), maxSuggestions: args["maxActions"] as? Int ?? 20)))
        case "cuyscout_observe": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.observe(sessionID: required(args, "sessionId"), maxActions: args["maxActions"] as? Int ?? 20)))
        case "cuyscout_navigation_graph": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.navigationGraph(sessionID: required(args, "sessionId"))))
        case "cuyscout_create_checkpoint": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.createCheckpoint(sessionID: required(args, "sessionId"), name: required(args, "name"))))
        case "cuyscout_list_checkpoints": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.listCheckpoints(sessionID: required(args, "sessionId"))))
        case "cuyscout_restore_checkpoint": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.restoreCheckpoint(sessionID: required(args, "sessionId"), checkpointID: required(args, "checkpointId"), resetApp: args["resetApp"] as? Bool ?? false)))
        case "cuyscout_accept_alert": _ = try engine.perform(.acceptAlert, sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_dismiss_alert": _ = try engine.perform(.dismissAlert, sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_get_alert_text": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.alertSnapshot(sessionID: required(args, "sessionId"))))
        case "cuyscout_get_contexts": value = try engine.webViewContexts(sessionID: required(args, "sessionId"))
        case "cuyscout_webview_status": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.webViewStatus(sessionID: required(args, "sessionId"))))
        case "cuyscout_register_webview": let contexts = args["contexts"] as? [String] ?? []; try engine.registerWebView(sessionID: required(args, "sessionId"), contexts: contexts); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.webViewStatus(sessionID: required(args, "sessionId"))))
        case "cuyscout_poll_webview": value = try engine.pollWebView(sessionID: required(args, "sessionId")).map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        case "cuyscout_complete_webview": let commandID = try required(args, "commandID"); let result = WebViewResult(commandID: commandID, success: args["success"] as? Bool ?? false, valueJSON: args["valueJSON"] as? String, error: args["error"] as? String); try engine.completeWebView(sessionID: required(args, "sessionId"), result: result); value = ["accepted": true]
        case "cuyscout_set_context": let context = try required(args, "context"); try engine.setContext(sessionID: try required(args, "sessionId"), context: context); value = ["context": context]
        case "cuyscout_execute_script":
            let sessionID = try required(args, "sessionId"); let script = try required(args, "script"); let scriptArgs = args["args"] as? [Any] ?? []; let encodedArgs = (try? JSONSerialization.data(withJSONObject: scriptArgs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"; let result = try engine.executeWebViewScript(sessionID: sessionID, script: script, argumentsJSON: encodedArgs); value = result.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) ?? $0 } ?? NSNull()
        case "cuyscout_poll_xctest": value = try engine.pollBridge(sessionID: required(args, "sessionId")).map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        case "cuyscout_start_recording": try engine.startRecording(sessionID: required(args, "sessionId")); value = ["recording": true]
        case "cuyscout_stop_recording": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.stopRecording(sessionID: required(args, "sessionId"))))
        case "cuyscout_get_recording": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.redactedRecording(sessionID: required(args, "sessionId"))))
        case "cuyscout_get_test_plan": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.testPlan(sessionID: required(args, "sessionId"))))
        case "cuyscout_validate_test_plan": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.validateTestPlan(sessionID: required(args, "sessionId"))))
        case "cuyscout_get_optimized_test_plan": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.optimizedTestPlan(sessionID: required(args, "sessionId"))))
        case "cuyscout_replay_recording": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.replayRecording(sessionID: required(args, "sessionId"), optimized: args["optimized"] as? Bool ?? false, variables: args["variables"] as? [String: String] ?? [:], resilient: args["resilient"] as? Bool ?? false, resetApp: args["resetApp"] as? Bool ?? false)))
        case "cuyscout_export_replay_junit": value = ["format": "junit-xml", "xml": try engine.replayRecording(sessionID: required(args, "sessionId"), optimized: args["optimized"] as? Bool ?? false, variables: args["variables"] as? [String: String] ?? [:], resilient: args["resilient"] as? Bool ?? false).junitXML]
        case "cuyscout_repair_selector": let strategy = ScoutSelector.Strategy(rawValue: try required(args, "strategy")) ?? .label; value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.repairSelector(sessionID: required(args, "sessionId"), selector: ScoutSelector(strategy: strategy, value: try required(args, "value")), limit: args["limit"] as? Int ?? 5)))
        case "cuyscout_preview_repair": let action = try JSONDecoder().decode(ScoutAction.self, from: JSONSerialization.data(withJSONObject: args["action"] as? [String: Any] ?? [:])); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.previewSelectorRepair(sessionID: required(args, "sessionId"), action: action, limit: args["limit"] as? Int ?? 5)))
        case "cuyscout_repair_audit": if let proposalObject = args["proposal"] as? [String: Any], let rawDecision = args["decision"] as? String, let decision = RepairAuditEntry.Decision(rawValue: rawDecision) { let proposal = try JSONDecoder().decode(ActionRepairProposal.self, from: JSONSerialization.data(withJSONObject: proposalObject)); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.recordRepairDecision(sessionID: required(args, "sessionId"), proposal: proposal, decision: decision))) } else { value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.repairAudit(sessionID: required(args, "sessionId"), limit: args["limit"] as? Int ?? 100))) }
        case "cuyscout_accessibility_audit": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.accessibilityAudit(sessionID: required(args, "sessionId"))))
        case "cuyscout_session_report": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.sessionReport(sessionID: required(args, "sessionId"))))
        case "cuyscout_export_report_html": value = ["format": "html", "html": try engine.sessionReportHTML(sessionID: required(args, "sessionId"))]
        case "cuyscout_get_security_policy": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.securityPolicy(sessionID: required(args, "sessionId"))))
        case "cuyscout_set_security_policy": let policy = try JSONDecoder().decode(SecurityPolicy.self, from: JSONSerialization.data(withJSONObject: args["policy"] as? [String: Any] ?? [:])); try engine.setSecurityPolicy(sessionID: required(args, "sessionId"), policy: policy); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(policy))
        case "cuyscout_start_exploration": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.startExploration(sessionID: required(args, "sessionId"), limits: ExplorationLimits(maxActions: args["maxActions"] as? Int ?? 100, maxStateRepeats: args["maxStateRepeats"] as? Int ?? 3, maxActionRepeats: args["maxActionRepeats"] as? Int ?? 4, timeoutSeconds: args["timeoutSeconds"] as? Double ?? 600))))
        case "cuyscout_exploration_status": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.explorationStatus(sessionID: required(args, "sessionId"))))
        case "cuyscout_stop_exploration": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.stopExploration(sessionID: required(args, "sessionId"))))
        case "cuyscout_export_appium": value = ["format": "appium-webdriverio", "code": try engine.redactedRecording(sessionID: required(args, "sessionId")).generatedAppium]
        case "cuyscout_export_appium_typescript": value = ["format": "appium-webdriverio-typescript", "code": try engine.redactedRecording(sessionID: required(args, "sessionId")).generatedAppiumTypeScript]
        case "cuyscout_export_appium_python": value = ["format": "appium-python-client", "code": try engine.redactedRecording(sessionID: required(args, "sessionId")).generatedAppiumPython]
        case "cuyscout_export_appium_java": value = ["format": "appium-java-junit", "code": try engine.redactedRecording(sessionID: required(args, "sessionId")).generatedAppiumJava]
        case "cuyscout_export_gherkin": value = ["format": "gherkin", "code": try engine.redactedRecording(sessionID: required(args, "sessionId")).generatedGherkin]
        case "cuyscout_export_portable": value = ["format": "cuyScout-json", "code": try engine.redactedRecording(sessionID: required(args, "sessionId")).portableJSON]
        case "cuyscout_execute":
            let action = try JSONDecoder().decode(ScoutAction.self, from: JSONSerialization.data(withJSONObject: args["action"] as? [String: Any] ?? [:])); let payload = try engine.perform(action, sessionID: required(args, "sessionId")); value = payload.map { ["base64": $0.base64EncodedString()] } ?? ["ok": true]
        case "cuyscout_execute_resilient":
            let action = try JSONDecoder().decode(ScoutAction.self, from: JSONSerialization.data(withJSONObject: args["action"] as? [String: Any] ?? [:])); let payload = try engine.performWithSelectorRepair(action, sessionID: required(args, "sessionId")); value = payload.map { ["base64": $0.base64EncodedString()] } ?? ["ok": true]
        case "cuyscout_execute_batch":
            let actionsData = try JSONSerialization.data(withJSONObject: args["actions"] as? [[String: Any]] ?? []); let actions = try JSONDecoder().decode([ScoutAction].self, from: actionsData); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.executeBatch(actions, sessionID: required(args, "sessionId"), resilient: args["resilient"] as? Bool ?? false, stopOnError: args["stopOnError"] as? Bool ?? true, includeResults: args["includeResults"] as? Bool ?? false, requestID: args["requestId"] as? String, timeoutSeconds: args["timeoutSeconds"] as? Double ?? 120, retryInfrastructure: args["retryInfrastructure"] as? Bool ?? false, maxRetries: args["maxRetries"] as? Int ?? 1)))
        case "cuyscout_batch_summary": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.batchSummary(sessionID: required(args, "sessionId"), requestID: args["requestId"] as? String)))
        case "cuyscout_cancel_batch": let sessionID = try required(args, "sessionId"); let requestID = try required(args, "requestId"); try engine.cancelBatch(sessionID: sessionID, requestID: requestID); value = ["cancelled": true, "requestId": requestID]
        case "cuyscout_validate_batch":
            let actionsData = try JSONSerialization.data(withJSONObject: args["actions"] as? [[String: Any]] ?? []); let actions = try JSONDecoder().decode([ScoutAction].self, from: actionsData); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.validateBatch(actions, sessionID: required(args, "sessionId"))))
        case "cuyscout_exploration_coverage": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.explorationCoverage(sessionID: required(args, "sessionId"))))
        case "cuyscout_session_readiness": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.sessionReadiness(sessionID: required(args, "sessionId"))))
        case "cuyscout_session_health": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.sessionHealth(sessionID: required(args, "sessionId"))))
        case "cuyscout_get_timeouts": value = try engine.getTimeouts(sessionID: required(args, "sessionId"))
        case "cuyscout_set_timeouts": let timeouts = (args["timeouts"] as? [String: Any] ?? [:]).compactMapValues { value in (value as? Double) ?? (value as? Int).map(Double.init) }; try engine.updateTimeouts(sessionID: required(args, "sessionId"), values: timeouts); value = try engine.getTimeouts(sessionID: required(args, "sessionId"))
        case "cuyscout_window_rect": value = try engine.windowRect(sessionID: required(args, "sessionId"))
        case "cuyscout_set_window_rect": try engine.setWindowRect(sessionID: required(args, "sessionId"), x: (args["x"] as? Double) ?? 0, y: (args["y"] as? Double) ?? 0, width: (args["width"] as? Double) ?? 0, height: (args["height"] as? Double) ?? 0); value = ["ok": true]
        case "cuyscout_element_selected": let data = try engine.performElementAction(sessionID: required(args, "sessionId"), elementID: required(args, "elementId")) { .elementSelected($0) } ?? Data(); value = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
        case "cuyscout_element_name": let data = try engine.performElementAction(sessionID: required(args, "sessionId"), elementID: required(args, "elementId")) { .elementName($0) } ?? Data(); value = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
        case "cuyscout_element_property": let propertyName = try required(args, "name"); let data = try engine.performElementAction(sessionID: required(args, "sessionId"), elementID: required(args, "elementId")) { .elementProperty($0, name: propertyName) } ?? Data(); value = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
        case "cuyscout_active_element": value = try engine.activeElement(sessionID: required(args, "sessionId")).map { ["elementId": $0] } ?? NSNull()
        case "cuyscout_set_alert_text": try engine.setAlertText(sessionID: required(args, "sessionId"), text: required(args, "text")); value = ["ok": true]
        case "cuyscout_get_cookies": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cookies(sessionID: required(args, "sessionId"))))
        case "cuyscout_add_cookie": let cookieDict = args["cookie"] as? [String: Any] ?? [:]; let cookie = Cookie(name: cookieDict["name"] as? String ?? "", value: cookieDict["value"] as? String ?? "", path: cookieDict["path"] as? String, domain: cookieDict["domain"] as? String, secure: cookieDict["secure"] as? Bool ?? false, httpOnly: cookieDict["httpOnly"] as? Bool ?? false, expiry: (cookieDict["expiry"] as? Double) ?? (cookieDict["expiry"] as? Int).map(Double.init)); try engine.addCookie(sessionID: required(args, "sessionId"), cookie: cookie); value = ["ok": true]
        case "cuyscout_delete_cookie": try engine.deleteCookie(sessionID: required(args, "sessionId"), name: required(args, "name")); value = ["ok": true]
        case "cuyscout_delete_all_cookies": try engine.deleteAllCookies(sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_scroll": _ = try engine.perform(.scroll(x: (args["x"] as? Double) ?? 0, y: (args["y"] as? Double) ?? 0), sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_grant_permission": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.grantPermission(sessionID: required(args, "sessionId"), bundleIdentifier: required(args, "bundleId"), service: required(args, "service"))))
        case "cuyscout_set_biometry": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.setBiometry(sessionID: required(args, "sessionId"), enrolled: args["enrolled"] as? Bool ?? true, enabled: args["enabled"] as? Bool ?? true)))
        case "cuyscout_set_location": try engine.setLocation(sessionID: required(args, "sessionId"), latitude: (args["latitude"] as? Double) ?? 0, longitude: (args["longitude"] as? Double) ?? 0); value = ["ok": true]
        case "cuyscout_visual_diff": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.visualDiff(sessionID: required(args, "sessionId"), tolerance: (args["tolerance"] as? Double) ?? 0.1)))
        case "cuyscout_timeline": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.timeline(sessionID: required(args, "sessionId"), includeScreenshots: args["screenshots"] as? Bool ?? false)))
        case "cuyscout_enqueue_session": let priority = (args["priority"] as? String).flatMap(SessionPriority.init(rawValue:)) ?? .normal; value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.enqueueSession(deviceID: args["deviceId"] as? String, bundleIdentifier: args["bundleIdentifier"] as? String, driverID: args["driverId"] as? String ?? "ios-simulator", priority: priority)))
        case "cuyscout_session_queue": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.sessionQueueSnapshot()))
        case "cuyscout_cancel_queued_session": value = ["cancelled": engine.cancelQueuedSession(sessionID: try required(args, "sessionId"))]
        case "cuyscout_fleet_dashboard": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.fleetDashboard()))
        case "cuyscout_register_worker": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.registerFarmWorker(url: required(args, "url"), capabilities: args["capabilities"] as? [String] ?? [], maxSessions: args["maxSessions"] as? Int ?? 4)))
        case "cuyscout_list_workers": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.farmWorkersStatus()))
        case "cuyscout_worker_heartbeat": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.farmWorkerHeartbeat(workerID: required(args, "workerId"), activeSessions: args["activeSessions"] as? Int)))
        case "cuyscout_cache_app": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.cacheApp(bundleIdentifier: required(args, "bundleId"), path: required(args, "path"))))
        case "cuyscout_app_cache_list": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.appCacheList()))
        case "cuyscout_clear_app_cache": engine.clearAppCache(bundleIdentifier: args["bundleId"] as? String); value = ["cleared": true]
        case "cuyscout_console_logs": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.consoleLogs(sessionID: required(args, "sessionId"), after: args["after"] as? Int ?? 0)))
        case "cuyscout_record_console_log": try engine.recordConsoleLog(sessionID: required(args, "sessionId"), level: args["level"] as? String ?? "info", message: required(args, "message"), source: args["source"] as? String); value = ["recorded": true]
        case "cuyscout_add_reactive_rule": let rule = try JSONDecoder().decode(ReactiveRule.self, from: JSONSerialization.data(withJSONObject: args["rule"] as? [String: Any] ?? [:])); try engine.addReactiveRule(sessionID: required(args, "sessionId"), rule: rule); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rule))
        case "cuyscout_reactive_rules": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.reactiveRulesList(sessionID: required(args, "sessionId"))))
        case "cuyscout_remove_reactive_rule": value = ["removed": try engine.removeReactiveRule(sessionID: required(args, "sessionId"), ruleID: required(args, "ruleId"))]
        case "cuyscout_record_fingerprint": let frame = args["frame"] as? [String: Any] ?? [:]; let frameDoubles = Dictionary(uniqueKeysWithValues: frame.compactMap { (k, v) -> (String, Double)? in if let d = v as? Double { return (k, d) }; if let i = v as? Int { return (k, Double(i)) }; return nil }); try engine.recordFingerprint(sessionID: required(args, "sessionId"), elementID: required(args, "elementId"), identifier: args["identifier"] as? String ?? "", label: args["label"] as? String ?? "", elementType: args["type"] as? String ?? "", frame: frameDoubles); value = ["recorded": true]
        case "cuyscout_fingerprints": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.fingerprints(sessionID: required(args, "sessionId"))))
        case "cuyscout_match_fingerprint": value = try engine.matchFingerprint(sessionID: required(args, "sessionId"), identifier: args["identifier"] as? String, label: args["label"] as? String, elementType: args["type"] as? String).map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        case "cuyscout_compare_behavior": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.compareBehavior(sessionID: required(args, "sessionId"), expectedSuccess: args["expectedSuccess"] as? Bool ?? true, actualSuccess: args["actualSuccess"] as? Bool ?? false, expectedError: args["expectedError"] as? String)))
        case "cuyscout_driver_manifests": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.driverManifests()))
        case "cuyscout_register_driver_manifest": let manifest = try JSONDecoder().decode(DriverManifest.self, from: JSONSerialization.data(withJSONObject: args["manifest"] as? [String: Any] ?? [:])); engine.registerDriverManifest(manifest); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest))
        case "cuyscout_load_driver": let manifest = try JSONDecoder().decode(DriverManifest.self, from: JSONSerialization.data(withJSONObject: args["manifest"] as? [String: Any] ?? [:])); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.loadDriverFromManifest(manifest)))
        case "cuyscout_plugin_routes": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.pluginRoutes()))
        case "cuyscout_record_network_request": try engine.recordNetworkRequest(sessionID: required(args, "sessionId"), method: required(args, "method"), url: required(args, "url"), status: args["status"] as? Int ?? 0, requestSize: args["requestSize"] as? Int ?? 0, responseSize: args["responseSize"] as? Int ?? 0, durationMilliseconds: args["durationMilliseconds"] as? Int ?? 0); value = ["recorded": true]
        case "cuyscout_network_requests": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.networkRequestsList(sessionID: required(args, "sessionId"), after: args["after"] as? Int ?? 0)))
        case "cuyscout_set_shard": try engine.setShardConfig(sessionID: required(args, "sessionId"), shardIndex: args["shardIndex"] as? Int ?? 0, shardCount: args["shardCount"] as? Int ?? 1); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.shardConfig(sessionID: required(args, "sessionId"))))
        case "cuyscout_get_shard": value = try engine.shardConfig(sessionID: required(args, "sessionId")).map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        case "cuyscout_record_otel_span": let span = try JSONDecoder().decode(OtelSpan.self, from: JSONSerialization.data(withJSONObject: args["span"] as? [String: Any] ?? [:])); try engine.recordOtelSpan(sessionID: required(args, "sessionId"), span: span); value = ["recorded": true]
        case "cuyscout_otel_spans": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.otelSpansList(sessionID: required(args, "sessionId"))))
        case "cuyscout_set_appearance": try engine.setAppearance(sessionID: required(args, "sessionId"), mode: required(args, "mode")); value = ["ok": true]
        case "cuyscout_set_status_bar": let config = StatusBarConfig(time: args["time"] as? String, dataNetwork: args["dataNetwork"] as? String, wifiMode: args["wifiMode"] as? String, batteryLevel: args["batteryLevel"] as? Int, batteryState: args["batteryState"] as? String); try engine.setStatusBar(sessionID: required(args, "sessionId"), config: config); value = ["ok": true]
        case "cuyscout_start_video_recording": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.startVideoRecording(sessionID: required(args, "sessionId"), path: required(args, "path"))))
        case "cuyscout_stop_video_recording": try engine.stopVideoRecording(sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_list_apps": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.listInstalledApps(sessionID: required(args, "sessionId"))))
        case "cuyscout_reset_keychain": try engine.resetKeychain(sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_deep_link": try engine.deepLink(sessionID: required(args, "sessionId"), url: required(args, "url")); value = ["ok": true]
        case "cuyscout_push_notification": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.pushNotification(sessionID: required(args, "sessionId"), bundleIdentifier: required(args, "bundleId"), payloadPath: required(args, "payloadPath"))))
        case "cuyscout_set_content_size": try engine.setContentSize(sessionID: required(args, "sessionId"), size: required(args, "size")); value = ["ok": true]
        case "cuyscout_add_media": try engine.addMedia(sessionID: required(args, "sessionId"), path: required(args, "path")); value = ["ok": true]
        case "cuyscout_spawn": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.spawnProcess(sessionID: required(args, "sessionId"), bundleIdentifier: required(args, "bundleId"), args: args["args"] as? [String] ?? [])))
        case "cuyscout_icloud_sync": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.icloudSync(sessionID: required(args, "sessionId"))))
        case "cuyscout_element_location": value = try engine.elementLocation(sessionID: required(args, "sessionId"), elementID: required(args, "elementId"))
        case "cuyscout_element_size": value = try engine.elementSize(sessionID: required(args, "sessionId"), elementID: required(args, "elementId"))
        case "cuyscout_shake": try engine.shake(sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_get_appearance": value = try engine.appearance(sessionID: required(args, "sessionId"))
        case "cuyscout_get_content_size": value = try engine.contentSize(sessionID: required(args, "sessionId"))
        case "cuyscout_enumerate_files": value = try engine.enumerateFiles(sessionID: required(args, "sessionId"), path: required(args, "path"))
        case "cuyscout_double_tap": _ = try engine.performElementAction(sessionID: required(args, "sessionId"), elementID: required(args, "elementId")) { .doubleTap($0) }; value = ["ok": true]
        case "cuyscout_long_press": let duration = (args["duration"] as? Double) ?? 1.0; _ = try engine.performElementAction(sessionID: required(args, "sessionId"), elementID: required(args, "elementId")) { .longPress($0, duration: duration) }; value = ["ok": true]
        case "cuyscout_pinch": let scale = (args["scale"] as? Double) ?? 2.0; let velocity = (args["velocity"] as? Double) ?? 1.0; _ = try engine.performElementAction(sessionID: required(args, "sessionId"), elementID: required(args, "elementId")) { _ in .pinch(scale: scale, velocity: velocity) }; value = ["ok": true]
        case "cuyscout_boot_device": try engine.bootDevice(deviceID: required(args, "deviceId")); value = ["ok": true]
        case "cuyscout_shutdown_device": try engine.shutdownDevice(deviceID: required(args, "deviceId")); value = ["ok": true]
        case "cuyscout_erase_device": try engine.eraseDevice(deviceID: required(args, "deviceId")); value = ["ok": true]
        case "cuyscout_clone_device": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.cloneDevice(sourceDeviceID: required(args, "deviceId"), name: required(args, "name"))))
        case "cuyscout_delete_device": try engine.deleteDevice(deviceID: required(args, "deviceId")); value = ["ok": true]
        case "cuyscout_create_device": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.createDevice(name: required(args, "name"), runtime: required(args, "runtime"))))
        case "cuyscout_rename_device": try engine.renameDevice(deviceID: required(args, "deviceId"), name: required(args, "name")); value = ["ok": true]
        case "cuyscout_pbsync": try engine.pbsync(sessionID: required(args, "sessionId")); value = ["ok": true]
        case "cuyscout_download_file": try engine.downloadFile(sessionID: required(args, "sessionId"), source: required(args, "source"), destination: required(args, "destination")); value = ["ok": true]
        case "cuyscout_upload_file": try engine.uploadFile(sessionID: required(args, "sessionId"), source: required(args, "source"), destination: required(args, "destination")); value = ["ok": true]
        case "cuyscout_get_app_container": value = try engine.getAppContainer(sessionID: required(args, "sessionId"), bundleIdentifier: required(args, "bundleId"), container: args["container"] as? String ?? "data")
        case "cuyscout_get_config": value = try engine.getConfig(sessionID: required(args, "sessionId"), key: required(args, "key"))
        case "cuyscout_set_config": try engine.setConfig(sessionID: required(args, "sessionId"), key: required(args, "key"), value: required(args, "value")); value = ["ok": true]
        case "cuyscout_verify_test_plan": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.verifyTestPlan(sessionID: required(args, "sessionId"), format: args["format"] as? String ?? "xctest", resetApp: args["resetApp"] as? Bool ?? true)))
        case "cuyscout_accessibility_overlay": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.accessibilityOverlay(sessionID: required(args, "sessionId"))))
        case "cuyscout_visual_compare_region": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.visualCompareRegion(sessionID: required(args, "sessionId"), x: (args["x"] as? Double) ?? 0, y: (args["y"] as? Double) ?? 0, width: (args["width"] as? Double) ?? 0, height: (args["height"] as? Double) ?? 0, tolerance: (args["tolerance"] as? Double) ?? 0.1)))
        case "cuyscout_set_plugin_security_policy": let policy = try JSONDecoder().decode(PluginSecurityPolicy.self, from: JSONSerialization.data(withJSONObject: args["policy"] as? [String: Any] ?? [:])); engine.setPluginSecurityPolicy(policy); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(policy))
        case "cuyscout_detect_cycles": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.detectCycles(sessionID: required(args, "sessionId"))))
        case "cuyscout_ocr": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.recognizeText(sessionID: required(args, "sessionId"), x: args["x"] as? Double, y: args["y"] as? Double, width: args["width"] as? Double, height: args["height"] as? Double)))
        case "cuyscout_build_runner": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try engine.buildRunner(projectPath: required(args, "projectPath"), scheme: required(args, "scheme"), destination: required(args, "destination"), signingIdentity: args["signingIdentity"] as? String)))
        case "cuyscout_generate_screen_contract": value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.generateScreenContract(sessionID: required(args, "sessionId"), name: args["name"] as? String ?? "screen")))
        case "cuyscout_compare_screen_contract": let contract = try JSONDecoder().decode(ScreenContract.self, from: JSONSerialization.data(withJSONObject: args["contract"] as? [String: Any] ?? [:])); value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.compareScreenContract(sessionID: required(args, "sessionId"), contract: contract)))
        default: throw ScoutError.invalidRequest("Unknown MCP tool: \(name)")
        }
        return toolResult(id: id, value: value)
    }

    private func toolResult(id: Any, value: Any, isError: Bool = false) -> [String: Any] {
        let object: Any = value is [String: Any] ? value : ["value": value]
        let data = try? JSONSerialization.data(withJSONObject: object)
        let text = data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return ["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": text]], "structuredContent": object, "isError": isError]]
    }

    private func required(_ args: [String: Any], _ key: String) throws -> String { guard let value = args[key] as? String, !value.isEmpty else { throw ScoutError.invalidRequest("Missing argument: \(key)") }; return value }
    private func write(_ object: [String: Any]) { guard let data = try? JSONSerialization.data(withJSONObject: object), let line = String(data: data, encoding: .utf8) else { return }; output.write(Data((line + "\n").utf8)) }
}

MCPServer().run()
