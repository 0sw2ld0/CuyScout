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
    private let bearerToken: String?
    private let app: XCUIApplication
    private let maxSeconds: Double
    private let stopFilePath = "/tmp/cuyscout-bridge-stop"
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // iOS can hold a local-network request while its permission sheet is open.
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

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
        bearerToken = env["CUYSCOUT_TOKEN"] ?? file["token"] as? String
        app = XCUIApplication(bundleIdentifier: rawBundle)
        maxSeconds = env["CUYSCOUT_MAX_SECONDS"].flatMap(Double.init) ?? file["maxSeconds"] as? Double ?? 600
    }

    func run() throws {
        try? FileManager.default.removeItem(atPath: stopFilePath)
        let physicalDevice = ProcessInfo.processInfo.environment["CUYSCOUT_PHYSICAL_DEVICE"] == "true"
        if physicalDevice {
            // A UI-test process runs in the background. iOS denies its first local-network
            // request without showing the consent sheet unless its xctrunner is foreground.
            // Foreground it only for consent; never press the user's Allow button ourselves.
            let runnerID = Bundle.main.bundleIdentifier ?? "com.cuyscout.runner.uitests.xctrunner"
            XCUIApplication(bundleIdentifier: runnerID).activate()
        }
        post("/session/\(sessionID)/bridge", body: Data())
        if physicalDevice {
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if alert.waitForExistence(timeout: 5) {
                let consentDeadline = Date().addingTimeInterval(90)
                while alert.exists && Date() < consentDeadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                }
            }
            // The first request can fail while consent is pending; retry registration.
            post("/session/\(sessionID)/bridge", body: Data())
        }
        let preserve = (ProcessInfo.processInfo.environment["CUYSCOUT_PRESERVE_RUNNING_APP"] ?? "false") == "true"
        if preserve && app.state != .notRunning { app.activate() }
        else { app.launch() }
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
        } catch {
            // El código viaja aparte del texto: el gateway lo traduce a un error W3C
            // (`no such element`), del que depende la autocuración de selectores.
            let nsError = error as NSError
            let code = nsError.domain == Self.errorDomain ? nsError.code : nil
            postResult(commandID: commandID, success: false, error: nsError.localizedDescription, errorCode: code)
        }
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
            let element = try resolve(required(selector, "selector"))
            try ensureNotHidden(element)
            element.tap(); return nil
        case "typeElement":
            let element = try resolve(required(selector, "selector"))
            try typeText(action["text"] as? String ?? "", into: element)
            return nil
        case "clearElement":
            let element = try resolve(required(selector, "selector")); let current = element.value as? String ?? ""
            if !current.isEmpty { try typeText(String(repeating: "\u{8}", count: current.count), into: element) }
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
            return try json(accessibilityTree(options: action["options"] as? [String: Any] ?? [:]))
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

    /// El selector `type` acepta el nombre semántico ("textField") y el rawValue histórico ("49").
    private func elementType(named name: String) -> XCUIElement.ElementType? {
        if let raw = UInt(name), let type = XCUIElement.ElementType(rawValue: raw) { return type }
        let all: [XCUIElement.ElementType] = [.button, .textField, .secureTextField, .textView, .searchField,
                                              .staticText, .image, .cell, .link, .switch, .slider, .picker,
                                              .pickerWheel, .datePicker, .segmentedControl, .scrollView, .table,
                                              .collectionView, .navigationBar, .tabBar, .alert, .sheet, .keyboard,
                                              .toggle, .checkBox, .stepper, .menuItem, .other]
        return all.first { typeName($0) == name }
    }

    /// La búsqueda se delega a una consulta de XCTest en vez de enumerar todos los elementos
    /// y comparar propiedad por propiedad: cada acceso a `identifier` o `label` sobre un
    /// `XCUIElement` es una consulta independiente, y en una pantalla real eso agota el
    /// timeout del puente. Un predicado resuelve todas las coincidencias de una vez.
    private func query(for selector: ScoutBridgeSelector) -> XCUIElementQuery? {
        switch selector.strategy {
        case "accessibilityIdentifier", "id":
            return app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", selector.value))
        case "label":
            return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", selector.value))
        case "value":
            return app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", selector.value))
        case "type":
            guard let type = elementType(named: selector.value) else { return nil }
            return app.descendants(matching: type)
        case "predicate":
            return app.descendants(matching: .any).matching(NSPredicate(format: selector.value))
        default:
            return nil
        }
    }

    private func resolveAll(_ selector: ScoutBridgeSelector) -> [XCUIElement] {
        query(for: selector)?.allElementsBoundByIndex ?? []
    }

    private func resolve(_ selector: ScoutBridgeSelector) throws -> XCUIElement {
        if let query = query(for: selector) {
            let element = query.firstMatch
            if element.exists {
                // Con coincidencias repetidas (una oculta, otra visible) se prefiere la visible.
                if element.isHittable { return element }
                let count = min(query.count, 5)
                if count > 1, let visible = (1..<count).lazy.map({ query.element(boundBy: $0) }).first(where: { $0.isHittable }) { return visible }
                return element
            }
        }
        // The password manager sheet belongs to SpringBoard, not the tested app.
        if selector.strategy == "label" {
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if alert.exists {
                let button = alert.buttons.matching(NSPredicate(format: "label == %@", selector.value)).firstMatch
                if button.exists { return button }
            }
        }
        throw notFound(selector)
    }

    /// Nombre semántico del tipo de elemento. El agente decide con esto si un control se
    /// escribe o se toca; un `rawValue` numérico no le dice nada y hace que un campo de
    /// texto parezca un botón más.
    private func typeName(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .textField: return "textField"
        case .secureTextField: return "secureTextField"
        case .textView: return "textView"
        case .searchField: return "searchField"
        case .staticText: return "staticText"
        case .image: return "image"
        case .cell: return "cell"
        case .link: return "link"
        case .switch: return "switch"
        case .slider: return "slider"
        case .picker, .pickerWheel: return "picker"
        case .datePicker: return "datePicker"
        case .segmentedControl: return "segmentedControl"
        case .scrollView: return "scrollView"
        case .table: return "table"
        case .collectionView: return "collectionView"
        case .navigationBar: return "navigationBar"
        case .tabBar: return "tabBar"
        case .alert: return "alert"
        case .keyboard: return "keyboard"
        case .toggle: return "toggle"
        case .checkBox: return "checkBox"
        case .stepper: return "stepper"
        case .menuItem: return "menuItem"
        case .application: return "application"
        case .window: return "window"
        case .sheet: return "sheet"
        case .other: return "other"
        default: return "type\(type.rawValue)"
        }
    }

    /// Escribe en un control asegurando primero el foco de teclado. `typeText` sobre un
    /// elemento sin foco es un fallo de XCTest, no un error recuperable, así que el foco se
    /// verifica antes: se toca el elemento, se espera el teclado software y, si aun así el
    /// foco quedó en otro sitio (contenedores SwiftUI que delegan en un hijo), se escribe
    /// contra la app, que dirige el texto al campo realmente enfocado.
    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasKeyboardFocus(element) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return hasKeyboardFocus(element)
    }

    /// Un elemento dentro de la pantalla que XCTest no puede tocar está oculto o tapado por
    /// otra vista: tocarlo pulsaría lo que haya encima. Fuera de la pantalla sí se permite,
    /// porque XCTest desplaza hasta él antes de tocar.
    private func ensureNotHidden(_ element: XCUIElement) throws {
        let frame = element.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let label = element.label.isEmpty ? "" : " '\(element.label.prefix(60))'"
        let hidden = Self.runnerError(Self.notVisibleErrorCode, "not_visible: el elemento \(typeName(element.elementType))\(label) existe pero está oculto o tapado en la pantalla actual; no se tocó")
        guard !frame.isEmpty, app.frame.contains(center) else { return }
        if !element.isHittable { throw hidden }
        // XCTest no considera otras ventanas al evaluar `isHittable`: se contrasta con el árbol.
        guard app.windows.count > 1, let root = try? app.snapshot() else { return }
        var all: [XCUIElementSnapshot] = []
        flatten(root, into: &all)
        let occluded = occludedIndices(in: all)
        guard !occluded.isEmpty else { return }
        let type = element.elementType, text = element.label
        let matches = all.indices.filter { all[$0].elementType == type && all[$0].label == text && all[$0].frame == frame }
        if !matches.isEmpty && matches.allSatisfy(occluded.contains) { throw hidden }
    }

    private static let editableTypes: [XCUIElement.ElementType] = [.textField, .secureTextField, .textView, .searchField]

    /// Campo al que va el texto: el propio elemento si es editable (o ya tiene el foco) o,
    /// en un contenedor, su único campo editable. Un botón u opción que solo *menciona* la
    /// clave no se toca: tocarlo para buscar un teclado lo activaría y cambiaría de pantalla.
    private func editableTarget(for element: XCUIElement) throws -> XCUIElement {
        if Self.editableTypes.contains(element.elementType) || hasKeyboardFocus(element) { return element }
        let rawTypes = Self.editableTypes.map { NSNumber(value: $0.rawValue) }
        let fields = element.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@", rawTypes))
        if fields.count == 1 { return fields.firstMatch }
        let kind = typeName(element.elementType)
        let label = element.label.isEmpty ? "" : " '\(element.label.prefix(60))'"
        let detail = fields.count > 1 ? "contiene \(fields.count) campos; apunta al campo concreto" : "no es un campo de texto y no se tocó"
        throw Self.runnerError(Self.notEditableErrorCode, "not_editable: el elemento es \(kind)\(label) y \(detail)")
    }

    private func typeText(_ text: String, into found: XCUIElement) throws {
        guard found.waitForExistence(timeout: 5) else { throw Self.notFoundCode("El elemento no existe para escribir") }
        let element = try editableTarget(for: found)
        try ensureNotHidden(element)
        if !hasKeyboardFocus(element) {
            element.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
            _ = waitForKeyboardFocus(element, timeout: 2)
        }
        // Un segundo toque solo cuando el teclado nunca apareció. Con el teclado arriba la
        // pantalla ya se desplazó y las coordenadas del elemento pueden caer sobre una tecla:
        // ese "reintento" escribiría un carácter extra en el campo.
        if !hasKeyboardFocus(element) && !app.keyboards.firstMatch.exists {
            element.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
            _ = waitForKeyboardFocus(element, timeout: 2)
        }
        guard app.keyboards.firstMatch.exists else { throw Self.runnerError(9, "No apareció el teclado software para escribir") }
        if hasKeyboardFocus(element) { element.typeText(text) } else { app.typeText(text) }
    }

    private func elementProperties(_ element: XCUIElement) -> [String: Any] {
        ["type": typeName(element.elementType), "typeCode": String(element.elementType.rawValue), "identifier": element.identifier, "label": element.label,
         "value": String(describing: element.value ?? ""), "enabled": element.isEnabled, "exists": element.exists,
         "frame": ["x": element.frame.origin.x, "y": element.frame.origin.y, "width": element.frame.width, "height": element.frame.height]]
    }

    private func isInteractive(_ type: XCUIElement.ElementType) -> Bool {
        switch type {
        case .button, .cell, .checkBox, .comboBox, .link, .menuItem, .picker, .pickerWheel, .radioButton,
             .searchField, .secureTextField, .slider, .stepper, .switch, .tab, .textField, .textView, .toggle:
            return true
        default: return false
        }
    }

    /// El árbol se construye desde UN solo `snapshot()` de la app y se recorre en memoria.
    /// Consultar `identifier`, `label`, `frame` o `isHittable` elemento por elemento sobre
    /// `XCUIElement` es un round-trip a XCTest por propiedad: en una pantalla con contenido
    /// real eso supera de largo el timeout del puente. El snapshot cuesta una sola consulta.
    private func snapshotProperties(_ snapshot: XCUIElementSnapshot) -> [String: Any] {
        ["type": typeName(snapshot.elementType), "typeCode": String(snapshot.elementType.rawValue),
         "identifier": snapshot.identifier, "label": snapshot.label,
         "value": String(describing: snapshot.value ?? ""), "enabled": snapshot.isEnabled, "exists": true,
         "frame": ["x": snapshot.frame.origin.x, "y": snapshot.frame.origin.y, "width": snapshot.frame.width, "height": snapshot.frame.height]]
    }

    private func flatten(_ snapshot: XCUIElementSnapshot, into result: inout [XCUIElementSnapshot]) {
        result.append(snapshot)
        for child in snapshot.children { flatten(child, into: &result) }
    }

    /// Índices (en `all`) de los elementos tapados por otra ventana. Algunas apps precargan
    /// una pantalla (p. ej. un formulario de login) en una ventana y muestran otra encima: el
    /// árbol conserva ambas y XCTest da por tocable lo de abajo. La ventana superior es la
    /// última del recorrido con contenido (controles o textos); lo que queda bajo ella está oculto.
    private func occludedIndices(in all: [XCUIElementSnapshot]) -> Set<Int> {
        var windowOf = Array(repeating: -1, count: all.count)
        // `all` está en preorden; se reconstruye a qué ventana pertenece cada nodo.
        func assign(_ snapshot: XCUIElementSnapshot, _ index: inout Int, window: Int) {
            let mine = index
            let owner = snapshot.elementType == .window ? mine : window
            windowOf[mine] = owner
            index += 1
            for child in snapshot.children { assign(child, &index, window: owner) }
        }
        var cursor = 0
        if let root = all.first { assign(root, &cursor, window: -1) }
        let windows = all.indices.filter { all[$0].elementType == .window }
        guard windows.count > 1 else { return [] }
        // La ventana que tapa es la más alta cuyo contenido (controles, textos, imágenes)
        // ocupa buena parte de la pantalla. Una ventana flotante pequeña (p. ej. un botón de
        // depuración) no tapa nada: sus elementos y los de debajo siguen visibles.
        let screenArea = max(1, all[0].frame.width * all[0].frame.height)
        let contentBounds: (Int) -> CGRect = { window in
            all.indices.reduce(CGRect.null) { bounds, index in
                let element = all[index]
                guard windowOf[index] == window, !element.frame.isEmpty,
                      self.isInteractive(element.elementType) || element.elementType == .image
                        || (element.elementType == .staticText && !element.label.isEmpty) else { return bounds }
                return bounds.union(element.frame)
            }
        }
        guard let top = windows.last(where: { window in
            let bounds = contentBounds(window)
            return !bounds.isNull && bounds.width * bounds.height >= screenArea * 0.4
        }) else { return [] }
        let cover = all[top].frame
        return Set(all.indices.filter { index in
            let owner = windowOf[index]
            guard owner >= 0, owner != top, (windows.firstIndex(of: owner) ?? 0) < (windows.firstIndex(of: top) ?? 0) else { return false }
            let frame = all[index].frame
            return !frame.isEmpty && cover.contains(CGPoint(x: frame.midX, y: frame.midY))
        })
    }

    private func accessibilityTree(options: [String: Any] = [:]) throws -> [String: Any] {
        if options["includeSystemAlerts"] as? Bool == true {
            let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            let applicationAlert = app.alerts.firstMatch
            let alert = systemAlert.exists ? systemAlert : applicationAlert
            if alert.exists {
                let buttons = alert.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
                let body = alert.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
                return ["bundleIdentifier": bundleIdentifier, "count": 0, "elements": [],
                        "activeAlert": ["text": ([alert.label] + body).filter { !$0.isEmpty }.joined(separator: " "), "buttons": buttons]]
            }
        }
        let visibleOnly = options["visibleOnly"] as? Bool ?? false
        let interactiveOnly = options["interactiveOnly"] as? Bool ?? false
        let hittableOnly = options["hittableOnly"] as? Bool ?? false
        let root = try app.snapshot()
        var all: [XCUIElementSnapshot] = []
        flatten(root, into: &all)
        let screen = root.frame
        // Posición de cada snapshot entre los de su mismo tipo: `descendants(matching:)`
        // recorre el árbol en el mismo orden, así se llega al XCUIElement sin buscar por texto.
        var ordinals: [Int] = Array(repeating: 0, count: all.count)
        var counters: [UInt: Int] = [:]
        for index in all.indices.dropFirst() {
            let key = all[index].elementType.rawValue
            ordinals[index] = counters[key, default: 0]
            counters[key, default: 0] += 1
        }
        var hittableChecks = 0
        let occluded = visibleOnly ? occludedIndices(in: all) : []
        var elements = all.indices.filter { index in
            let snapshot = all[index]
            if occluded.contains(index) { return false }
            // Sin `isHittable` en el snapshot, "visible" es tener área y caer dentro de la
            // pantalla: descarta lo que quedó fuera de vista al desplazarse.
            if visibleOnly && (snapshot.frame.isEmpty || !snapshot.frame.intersects(screen)) { return false }
            if interactiveOnly && !isInteractive(snapshot.elementType) { return false }
            // Un control dentro de la pantalla pero oculto o tapado (un formulario precargado
            // detrás de otra vista) no se ofrece: `isHittable` cuesta una consulta por control,
            // por eso solo se evalúa en los interactivos y con tope.
            if hittableOnly && index > 0 && isInteractive(snapshot.elementType) && hittableChecks < 40 {
                hittableChecks += 1
                if !app.descendants(matching: snapshot.elementType).element(boundBy: ordinals[index]).isHittable { return false }
            }
            return true
        }.map { all[$0] }
        if let maxElements = options["maxElements"] as? Int, elements.count > maxElements { elements = Array(elements.prefix(maxElements)) }
        let properties = elements.map(snapshotProperties)
        return ["bundleIdentifier": bundleIdentifier, "count": properties.count, "elements": properties]
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
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        request.setValue(body.isEmpty ? "0" : "\(body.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = executeRequest(request)
    }

    private func getJSON(_ path: String) -> [String: Any]? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"; request.timeoutInterval = 5
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        guard let data = executeRequest(request), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func postResult(commandID: String, success: Bool, payload: Data? = nil, error: String? = nil, errorCode: Int? = nil) {
        var body: [String: Any] = ["commandID": commandID, "success": success]
        if let payload { body["payloadBase64"] = payload.base64EncodedString() }
        if let error { body["error"] = error }
        if let errorCode { body["errorCode"] = errorCode }
        post("/session/\(sessionID)/bridge/result", body: try! JSONSerialization.data(withJSONObject: body))
    }

    // MARK: - Errores

    /// Códigos del runner que el gateway traduce: 7 = acción no soportada,
    /// 8 = elemento no encontrado (`no such element`), 9 = teclado ausente,
    /// 10 = el elemento no es editable y 11 = está oculto o tapado (`element not interactable`).
    static let errorDomain = "ScoutBridgeRunner"
    static let notFoundErrorCode = 8
    static let notEditableErrorCode = 10
    static let notVisibleErrorCode = 11

    private static func runnerError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: errorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func notFoundCode(_ message: String) -> NSError { runnerError(notFoundErrorCode, message) }
    private func notFound(_ selector: ScoutBridgeSelector) -> NSError {
        Self.notFoundCode("No se encontró el elemento: \(selector.strategy)=\(selector.value)")
    }
    private func required(_ selector: ScoutBridgeSelector?, _ field: String) throws -> ScoutBridgeSelector {
        guard let selector else { throw Self.runnerError(9, "El comando no incluye el selector '\(field)'") }
        return selector
    }
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
}

