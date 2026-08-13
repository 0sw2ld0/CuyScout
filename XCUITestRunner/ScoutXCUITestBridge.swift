import Foundation
import XCTest

/// Copia este archivo a un target UI Testing de Xcode.
/// Variables requeridas: CUYSCOUT_URL, CUYSCOUT_SESSION_ID y CUYSCOUT_BUNDLE_ID.
final class ScoutXCUITestBridge {
    private let baseURL: URL
    private let sessionID: String
    private let app: XCUIApplication
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        baseURL = URL(string: ProcessInfo.processInfo.environment["CUYSCOUT_URL"] ?? "http://127.0.0.1:4723")!
        sessionID = ProcessInfo.processInfo.environment["CUYSCOUT_SESSION_ID"]!
        app = XCUIApplication(bundleIdentifier: ProcessInfo.processInfo.environment["CUYSCOUT_BUNDLE_ID"]!)
    }

    func run() {
        post("/session/\(sessionID)/bridge", body: Data())
        app.launch()
        while true {
            if let command: BridgeCommand = get("/session/\(sessionID)/bridge/command") {
                execute(command)
            } else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
    }

    private func execute(_ command: BridgeCommand) {
        do {
            let payload = try perform(command.action)
            postResult(BridgeResult(commandID: command.id, success: true, payloadBase64: payload?.base64EncodedString()))
        } catch { postResult(BridgeResult(commandID: command.id, success: false, error: error.localizedDescription)) }
    }

    private func perform(_ action: ScoutAction) throws -> Data? {
        switch action {
        case .tap(let x, let y): app.coordinate(withNormalizedOffset: CGVector(dx: x / app.frame.width, dy: y / app.frame.height)).tap(); return nil
        case .swipe(let fx, let fy, let tx, let ty, let duration):
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: fx / app.frame.width, dy: fy / app.frame.height)); let end = app.coordinate(withNormalizedOffset: CGVector(dx: tx / app.frame.width, dy: ty / app.frame.height)); start.press(forDuration: duration, thenDragTo: end); return nil
        case .type(let text): app.typeText(text); return nil
        case .backgroundApp(let duration): XCUIDevice.shared.press(.home); if duration > 0 { Thread.sleep(forTimeInterval: duration) }; return nil
        case .findElement(let selector): return try elementJSON(resolve(selector))
        case .findElements(let selector): return try JSONSerialization.data(withJSONObject: ["elements": resolveAll(selector).map(elementProperties)])
        case .findElementFromElement(let parent, let child): let parentElement = try resolve(parent); let matches = resolveAllWithin(parentElement, child); guard let first = matches.first else { throw ScoutError.message("No se encontró el elemento relativo: \(child.strategy.rawValue)=\(child.value)") }; return try elementJSON(first)
        case .findElementsFromElement(let parent, let child): let parentElement = try resolve(parent); let matches = resolveAllWithin(parentElement, child); return try JSONSerialization.data(withJSONObject: ["elements": matches.map(elementProperties)])
        case .elementSelected(let selector): let element = try resolve(selector); return try JSONSerialization.data(withJSONObject: ["value": element.value as? Bool ?? false])
        case .elementName(let selector): let element = try resolve(selector); return try JSONSerialization.data(withJSONObject: ["value": element.label])
        case .elementProperty(let selector, let name): let element = try resolve(selector); let value: Any = name == "label" ? element.label : name == "value" ? String(describing: element.value ?? "") : name == "identifier" ? element.identifier : name == "enabled" ? element.isEnabled : name == "exists" ? element.exists : NSNull(); return try JSONSerialization.data(withJSONObject: ["value": value])
        case .scroll(let x, let y): app.swipeUp(); return nil
        case .alertText(let text): let alert = app.alerts.firstMatch; guard alert.waitForExistence(timeout: 2) else { throw ScoutError.message("No hay una alerta visible") }; let textField = alert.textFields.firstMatch; guard textField.waitForExistence(timeout: 2) else { throw ScoutError.message("La alerta no tiene campo de texto") }; textField.tap(); textField.typeText(text); return nil
        case .activeElement: return nil
        case .submit(let selector): try resolve(selector).tap(); return nil
        case .doubleTap(let selector): try resolve(selector).tap(); try resolve(selector).tap(); return nil
        case .longPress(let selector, let duration): let element = try resolve(selector); element.press(forDuration: duration); return nil
        case .pinch: return nil
        case .shake: return nil
        case .tapElement(let selector): try resolve(selector).tap(); return nil
        case .typeElement(let selector, let text): let element = try resolve(selector); try element.tap(); element.typeText(text); return nil
        case .waitFor(let selector, let timeout): guard resolve(selector).waitForExistence(timeout: timeout) else { throw ScoutError.message("No apareció el elemento dentro de \(timeout)s") }; return nil
        case .assertVisible(let selector): guard resolve(selector).exists else { throw ScoutError.message("El elemento no está visible") }; return nil
        case .assertText(let selector, let expected): let element = try resolve(selector); let actual = element.label.isEmpty ? String(describing: element.value ?? "") : element.label; guard actual == expected else { throw ScoutError.message("Texto esperado '\(expected)' pero se encontró '\(actual)'") }; return nil
        case .accessibilityTree: return try accessibilityJSON(AccessibilityOptions())
        case .accessibilityTreeWithOptions(let options): return try accessibilityJSON(options)
        case .accessibilityDiff(let options): return try accessibilityJSON(options)
        case .sequence(let actions): for action in actions { _ = try perform(action) }; return nil
        case .clearElement(let selector): try resolve(selector).clearText(); return nil
        case .elementAttribute(let selector, let name): let element = try resolve(selector); let value: Any = name == "identifier" ? element.identifier : name == "label" ? element.label : name == "value" ? String(describing: element.value ?? "") : name == "enabled" ? element.isEnabled : name == "exists" ? element.exists : NSNull(); return try JSONSerialization.data(withJSONObject: ["value": value])
        case .elementDisplayed(let selector): return try JSONSerialization.data(withJSONObject: ["value": resolve(selector).exists && resolve(selector).isHittable])
        case .elementEnabled(let selector): return try JSONSerialization.data(withJSONObject: ["value": resolve(selector).isEnabled])
        case .elementRect(let selector): let frame = resolve(selector).frame; return try JSONSerialization.data(withJSONObject: ["value": ["x": frame.origin.x, "y": frame.origin.y, "width": frame.width, "height": frame.height]])
        case .elementScreenshot(let selector): return XCUIScreenshot(element: resolve(selector)).pngRepresentation
        case .acceptAlert: return try handleAlert(dismiss: false)
        case .dismissAlert: return try handleAlert(dismiss: true)
        case .rotate(let orientation): XCUIDevice.shared.orientation = orientation == .portrait ? .portrait : orientation == .portraitUpsideDown ? .portraitUpsideDown : orientation == .landscapeLeft ? .landscapeLeft : .landscapeRight; return nil
        case .getClipboard: return try JSONSerialization.data(withJSONObject: ["value": UIPasteboard.general.string ?? ""])
        case .setClipboard(let text): UIPasteboard.general.string = text; return nil
        default: throw ScoutError.message("La acción no pertenece al runner UI")
        }
    }

    private func resolve(_ selector: ScoutSelector) throws -> XCUIElement {
        guard let element = resolveAll(selector).first else { throw ScoutError.message("No se encontró el elemento: \(selector.strategy.rawValue)=\(selector.value)") }
        return element
    }

    private func resolveAll(_ selector: ScoutSelector) -> [XCUIElement] {
        let matches = app.descendants(matching: .any).allElementsBoundByIndex.filter { element in
            switch selector.strategy {
            case .accessibilityIdentifier: return element.identifier == selector.value
            case .label: return element.label == selector.value
            case .value: return String(describing: element.value ?? "") == selector.value
            case .type: return String(describing: element.elementType.rawValue) == selector.value
            case .predicate: return NSPredicate(format: selector.value).evaluate(with: element)
            case .cssSelector, .xpath: return false
            }
        }
        return matches
    }

    private func resolveAllWithin(_ parent: XCUIElement, _ selector: ScoutSelector) -> [XCUIElement] {
        let matches = parent.descendants(matching: .any).allElementsBoundByIndex.filter { element in
            switch selector.strategy {
            case .accessibilityIdentifier: return element.identifier == selector.value
            case .label: return element.label == selector.value
            case .value: return String(describing: element.value ?? "") == selector.value
            case .type: return String(describing: element.elementType.rawValue) == selector.value
            case .predicate: return NSPredicate(format: selector.value).evaluate(with: element)
            case .cssSelector, .xpath: return false
            }
        }
        return matches
    }

    private func elementJSON(_ element: XCUIElement) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["element": elementProperties(element)])
    }

    private func accessibilityJSON(_ options: AccessibilityOptions) throws -> Data {
        var elements = app.descendants(matching: .any).allElementsBoundByIndex.filter { element in
            if options.visibleOnly && (!element.exists || element.frame.isEmpty) { return false }
            if options.interactiveOnly && !isInteractive(element) { return false }
            return true
        }.map(elementProperties)
        if let maxElements = options.maxElements, elements.count > maxElements { elements = Array(elements.prefix(maxElements)) }
        return try JSONSerialization.data(withJSONObject: ["bundleIdentifier": app.bundleID, "count": elements.count, "elements": elements])
    }

    private func elementProperties(_ element: XCUIElement) -> [String: Any] {
        [
            "type": String(describing: element.elementType.rawValue),
            "identifier": element.identifier,
            "label": element.label,
            "value": String(describing: element.value ?? ""),
            "enabled": element.isEnabled,
            "exists": element.exists,
            "frame": ["x": element.frame.origin.x, "y": element.frame.origin.y, "width": element.frame.width, "height": element.frame.height]
        ]
    }

    private func isInteractive(_ element: XCUIElement) -> Bool {
        switch element.elementType {
        case .button, .cell, .checkBox, .comboBox, .image, .key, .link, .menuItem, .picker, .radioButton, .scrollView, .secureTextField, .slider, .staticText, .switch, .tab, .textField, .textView: return true
        default: return false
        }
    }

    private func handleAlert(dismiss: Bool) throws -> Data {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { throw ScoutError.message("No hay una alerta del sistema visible") }
        let buttons = alert.buttons.allElementsBoundByIndex
        guard !buttons.isEmpty else { throw ScoutError.message("La alerta no tiene botones") }
        let index = dismiss && buttons.count > 1 ? buttons.count - 1 : 0
        buttons[index].tap()
        return try JSONSerialization.data(withJSONObject: ["value": true])
    }

    private func postResult(_ result: BridgeResult) { post("/session/\(sessionID)/bridge/result", body: try! encoder.encode(result)) }
    private func post(_ path: String, body: Data) { var request = URLRequest(url: baseURL.appendingPathComponent(path)); request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); URLSession.shared.dataTask(with: request).resume() }
    private func get<T: Decodable>(_ path: String) -> T? { let semaphore = DispatchSemaphore(value: 0); var result: T?; var request = URLRequest(url: baseURL.appendingPathComponent(path)); request.httpMethod = "GET"; URLSession.shared.dataTask(with: request) { data, _, _ in if let data, !data.isEmpty, data != Data("null".utf8) { result = try? self.decoder.decode(T.self, from: data) }; semaphore.signal() }.resume(); semaphore.wait(); return result }
}
