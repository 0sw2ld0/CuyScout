import Foundation
import XCTest

/// Runner XCUITest genérico que conecta una sesión de CuyScout con la app bajo prueba.
///
/// Protocolo del puente: `POST /session/:id/bridge` (alta), `GET /session/:id/bridge/command`
/// (poll de comandos) y `POST /session/:id/bridge/result` (entrega de resultados). El formato
/// del cable es el `BridgeCommand`/`BridgeResult` del servidor, decodificado con
/// `JSONSerialization` para no acoplar este target a CuyScoutCore.
///
/// Config: el gateway lanza `xcodebuild test-without-building` con variables
/// `TEST_RUNNER_CUYSCOUT_URL`/`TEST_RUNNER_CUYSCOUT_SESSION_ID`/`TEST_RUNNER_CUYSCOUT_BUNDLE_ID`/
/// `TEST_RUNNER_CUYSCOUT_CONFIG_FILE` (xcodebuild las reenvía al runner sin el prefijo). Fallback:
/// el archivo de config por sesión (`url`, `sessionId`, `bundleId`, `maxSeconds`) para
/// lanzamientos manuales. El ciclo termina al tocar `/tmp/cuyscout-bridge-stop`, al morir el
/// proceso (el gateway lo termina en DELETE) o al agotar `maxSeconds` (600 s por defecto).
final class ScoutBridgeRunner {
    private let baseURL: URL
    private let sessionID: String
    private let bundleIdentifier: String
    private let app: XCUIApplication
    private let maxSeconds: Double
    private let stopFilePath = "/tmp/cuyscout-bridge-stop"
    private let session = URLSession(configuration: .ephemeral)

    init() throws {
        let env = ProcessInfo.processInfo.environment
        // El gateway define TEST_RUNNER_CUYSCOUT_CONFIG_FILE con un archivo por sesión
        // (xcodebuild reenvía sin el prefijo); fallback al archivo histórico compartido.
        let configPath = env["CUYSCOUT_CONFIG_FILE"] ?? "/tmp/cuyscout-bridge.json"
        let file = (try? Data(contentsOf: URL(fileURLWithPath: configPath)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        let rawURL = env["CUYSCOUT_URL"] ?? file["url"] as? String ?? "http://127.0.0.1:4723"
        let rawSession = env["CUYSCOUT_SESSION_ID"] ?? file["sessionId"] as? String
        let rawBundle = env["CUYSCOUT_BUNDLE_ID"] ?? file["bundleId"] as? String
        guard let rawSession, !rawSession.isEmpty else { throw Self.runnerError(1, "Falta CUYSCOUT_SESSION_ID") }
        guard let rawBundle, !rawBundle.isEmpty else { throw Self.runnerError(2, "Falta CUYSCOUT_BUNDLE_ID") }
        guard let parsed = URL(string: rawURL) else { throw Self.runnerError(3, "CUYSCOUT_URL inválida: \(rawURL)") }
        baseURL = parsed; sessionID = rawSession; bundleIdentifier = rawBundle
        app = XCUIApplication(bundleIdentifier: rawBundle)
        maxSeconds = env["CUYSCOUT_MAX_SECONDS"].flatMap(Double.init) ?? file["maxSeconds"] as? Double ?? 600
    }

    func run() throws {
        try? FileManager.default.removeItem(atPath: stopFilePath)
        post("/session/\(sessionID)/bridge", body: Data())
        app.launch()
        let deadline = Date().addingTimeInterval(maxSeconds)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: stopFilePath) { return }
            if let command = getJSON("/session/\(sessionID)/bridge/command"),
               let id = command["id"] as? String,
               let action = command["action"] as? [String: Any] {
                execute(commandID: id, action: action)
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
    }

    // MARK: - Ejecución de acciones

    private func execute(commandID: String, action: [String: Any]) {
        do {
            let payload = try perform(action)
            postResult(commandID: commandID, success: true, payload: payload)
        } catch { postResult(commandID: commandID, success: false, error: "\(error)") }
    }

    private func perform(_ action: [String: Any]) throws -> Data? {
        let type = action["type"] as? String ?? ""
        let selector = (action["selector"] as? [String: Any]).flatMap(ScoutBridgeSelector.init(dict:))
        let parent = (action["parent"] as? [String: Any]).flatMap(ScoutBridgeSelector.init(dict:))
        let child = (action["child"] as? [String: Any]).flatMap(ScoutBridgeSelector.init(dict:))
        switch type {
        case "findElement":
            return try json(["element": elementProperties(try resolve(required(selector, "selector")))])
        case "findElements":
            return try json(["elements": resolveAll(required(selector, "selector")).map(elementProperties)])
        case "findElementFromElement":
            let scope = try resolve(try required(parent, "parent"))
            let matches = resolveAll(try required(child, "child")).filter { $0 != scope && scope.frame.contains($0.frame) }
            guard let first = matches.first else { throw notFound(try required(child, "child")) }
            return try json(["element": elementProperties(first)])
        case "findElementsFromElement":
            let scope = try resolve(try required(parent, "parent"))
            let matches = resolveAll(try required(child, "child")).filter { $0 != scope && scope.frame.contains($0.frame) }
            return try json(["elements": matches.map(elementProperties)])
        case "tapElement":
            try resolve(required(selector, "selector")).tap(); return nil
        case "typeElement":
            let element = try resolve(required(selector, "selector")); try element.tap()
            // Espera el teclado software: sin él typeText sintetiza contra el contenedor de
            // teclado oculto y falla con "no keyboard focus" (teclado hardware del simulador).
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
            element.typeText(action["text"] as? String ?? ""); return nil
        case "clearElement":
            let element = try resolve(required(selector, "selector")); let current = element.value as? String ?? ""; try element.tap()
            if !current.isEmpty { element.typeText(String(repeating: "\u{8}", count: current.count)) }
            return nil
        case "submit":
            try resolve(required(selector, "selector")).tap(); return nil
        case "doubleTap":
            let element = try resolve(required(selector, "selector")); try element.tap(); try element.tap(); return nil
        case "longPress":
            let element = try resolve(required(selector, "selector")); try element.press(forDuration: action["duration"] as? Double ?? 1.0); return nil
        case "elementSelected":
            let element = try resolve(required(selector, "selector"))
            return try json(["value": element.value as? Bool ?? false])
        case "elementName":
            return try json(["value": try resolve(required(selector, "selector")).label])
        case "elementAttribute", "elementProperty":
            let element = try resolve(required(selector, "selector")); let name = action["name"] as? String ?? ""
            let value: Any
            switch name {
            case "label": value = element.label
            case "value": value = String(describing: element.value ?? "")
            case "identifier": value = element.identifier
            case "enabled": value = element.isEnabled
            case "exists": value = element.exists
            default: value = NSNull()
            }
            return try json(["value": value])
        case "elementDisplayed":
            let element = try resolve(required(selector, "selector"))
            return try json(["value": element.exists && element.isHittable])
        case "elementEnabled":
            return try json(["value": try resolve(required(selector, "selector")).isEnabled])
        case "elementRect":
            let frame = try resolve(required(selector, "selector")).frame
            return try json(["value": ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height]])
        case "elementScreenshot":
            return (try resolve(required(selector, "selector"))).screenshot().pngRepresentation
        case "waitFor":
            let timeout = action["timeout"] as? Double ?? 10
            guard (try resolve(try required(selector, "selector"))).waitForExistence(timeout: timeout) else { throw Self.runnerError(4, "No apareció el elemento en \(timeout) s") }
            return nil
        case "assertVisible":
            guard (try resolve(try required(selector, "selector"))).exists else { throw Self.runnerError(5, "El elemento no está visible") }
            return nil
        case "assertText":
            let element = try resolve(required(selector, "selector"))
            let actual = element.label.isEmpty ? String(describing: element.value ?? "") : element.label
            let expected = action["expected"] as? String ?? ""
            guard actual == expected else { throw Self.runnerError(6, "Texto esperado '\(expected)' pero se encontró '\(actual)'") }
            return nil
        case "accessibilityTree", "accessibilityTreeWithOptions", "accessibilityDiff":
            return try json(accessibilityTree())
        case "tap":
            let x = action["x"] as? Double ?? 0; let y = action["y"] as? Double ?? 0
            let width = max(app.frame.width, 1); let height = max(app.frame.height, 1)
            app.coordinate(withNormalizedOffset: CGVector(dx: x / width, dy: y / height)).tap(); return nil
        case "type":
            app.typeText(action["text"] as? String ?? ""); return nil
        case "scroll":
            app.swipeUp(); return nil
        case "screenshot":
            return app.screenshot().pngRepresentation
        case "sequence":
            for nested in action["actions"] as? [[String: Any]] ?? [] { _ = try perform(nested) }
            return nil
        default:
            throw Self.runnerError(7, "Acción no soportada por el runner: \(type)")
        }
    }

    // MARK: - Resolución de elementos

    private struct ScoutBridgeSelector {
        let strategy: String
        let value: String
        init?(dict: [String: Any]) {
            guard let strategy = dict["strategy"] as? String, let value = dict["value"] as? String else { return nil }
            self.strategy = strategy; self.value = value
        }
    }

    private func matches(_ element: XCUIElement, _ selector: ScoutBridgeSelector) -> Bool {
        switch selector.strategy {
        case "accessibilityIdentifier", "id": return element.identifier == selector.value
        case "label": return element.label == selector.value
        case "value": return String(describing: element.value ?? "") == selector.value
        case "type": return String(element.elementType.rawValue) == selector.value
        case "predicate": return NSPredicate(format: selector.value).evaluate(with: element)
        default: return false
        }
    }

    private func resolveAll(_ selector: ScoutBridgeSelector) -> [XCUIElement] {
        app.descendants(matching: .any).allElementsBoundByIndex.filter { matches($0, selector) }
    }

    private func resolve(_ selector: ScoutBridgeSelector) throws -> XCUIElement {
        guard let element = resolveAll(selector).first else { throw notFound(selector) }
        return element
    }

    private func elementProperties(_ element: XCUIElement) -> [String: Any] {
        ["type": String(element.elementType.rawValue), "identifier": element.identifier, "label": element.label,
         "value": String(describing: element.value ?? ""), "enabled": element.isEnabled, "exists": element.exists,
         "frame": ["x": element.frame.origin.x, "y": element.frame.origin.y, "width": element.frame.width, "height": element.frame.height]]
    }

    private func accessibilityTree() throws -> [String: Any] {
        ["bundleIdentifier": bundleIdentifier, "count": 0, "elements": app.descendants(matching: .any).allElementsBoundByIndex.map(elementProperties)]
    }

    // MARK: - HTTP

    private func executeRequest(_ request: URLRequest) -> Data? {
        var result: Data?
        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
        semaphore.wait()
        return result
    }

    private func post(_ path: String, body: Data) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.httpBody = body.isEmpty ? nil : body
        request.setValue(body.isEmpty ? "0" : "\(body.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = executeRequest(request)
    }

    private func getJSON(_ path: String) -> [String: Any]? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"; request.timeoutInterval = 5
        guard let data = executeRequest(request), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func postResult(commandID: String, success: Bool, payload: Data? = nil, error: String? = nil) {
        var body: [String: Any] = ["commandID": commandID, "success": success]
        if let payload { body["payloadBase64"] = payload.base64EncodedString() }
        if let error { body["error"] = error }
        post("/session/\(sessionID)/bridge/result", body: try! JSONSerialization.data(withJSONObject: body))
    }

    // MARK: - Errores

    private static func runnerError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "ScoutBridgeRunner", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func notFound(_ selector: ScoutBridgeSelector) -> NSError {
        Self.runnerError(8, "No se encontró el elemento: \(selector.strategy)=\(selector.value)")
    }
    private func required(_ selector: ScoutBridgeSelector?, _ field: String) throws -> ScoutBridgeSelector {
        guard let selector else { throw Self.runnerError(9, "El comando no incluye el selector '\(field)'") }
        return selector
    }
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
}