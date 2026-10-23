import Foundation

/// Traduce una grabación de CuyScout a un flujo YAML de Maestro (https://maestro.dev).
/// Así una prueba que generó el agente se puede correr con `maestro test` o en Maestro Cloud
/// sin depender de CuyScout. Igual que el export a Appium: los intentos que fallaron al
/// grabar se saltan, las observaciones no se traducen y los valores ocultos pasan a variables.
public enum MaestroFlowExporter {
    public static func make(steps: [RecordedStep], appID: String?, name: String? = nil) -> String {
        var lines: [String] = [
            "# Generado por CuyScout desde una grabación. Ejecutar con: maestro test <archivo>.yaml",
            "# Los valores ocultos se pasan como variables: maestro test <archivo>.yaml -e PASO_3_TEXT=...",
            "# Las coordenadas están en puntos de pantalla, como en la grabación.",
        ]
        if let appID, !appID.isEmpty { lines.append("appId: \(quote(appID))") }
        if let name, !name.isEmpty { lines.append("name: \(quote(name))") }
        var variables: [String] = []
        var body: [String] = []
        // El replay de CuyScout reinicia la app antes de empezar; en Maestro eso es `launchApp`.
        if appID?.isEmpty == false, !steps.contains(where: { if case .launch = $0.action { return $0.success }; return false }) { body.append("- launchApp") }
        for step in steps where step.success {
            body += commands(for: step.action, path: "\(step.index)", appID: appID, variables: &variables)
        }
        if !variables.isEmpty {
            // Sin valor por defecto: un dato sensible no se escribe en el flujo.
            lines.insert("# Variables requeridas: " + variables.map { "-e \($0)=..." }.joined(separator: " "), at: 3)
        }
        lines.append("---")
        lines += body.isEmpty ? ["# La grabación no tiene pasos que actúen sobre la app."] : body
        return lines.joined(separator: "\n") + "\n"
    }

    /// Lee un artefacto `.cuyscout.json` y devuelve el flujo.
    public static func source(fromArtifactData data: Data, project: URL? = nil) throws -> String {
        let artifact: SessionArtifactBundle
        do { artifact = try JSONDecoder().decode(SessionArtifactBundle.self, from: data) }
        catch { throw ScoutError.invalidRequest("No se pudo leer el artefacto CuyScout: \(error.localizedDescription)") }
        guard let recording = artifact.recording, !recording.steps.isEmpty else {
            throw ScoutError.invalidRequest("Este artefacto no contiene una prueba grabada para exportar")
        }
        return make(steps: try FragmentExpansion.expand(recording.steps, platform: artifact.session.device.platform, project: project), appID: artifact.session.bundleIdentifier)
    }

    static func commands(for action: ScoutAction, path: String, appID: String?, variables: inout [String]) -> [String] {
        func value(_ text: String, field: String) -> String {
            guard text == "<redacted>" || text == "<text>" || text.isEmpty else { return quote(text) }
            let name = "PASO_" + path.replacingOccurrences(of: ".", with: "_") + "_" + field.uppercased()
            if !variables.contains(name) { variables.append(name) }
            return "${\(name)}"
        }
        switch action {
        case .launch(let bundle):
            return bundle == appID ? ["- launchApp"] : ["- launchApp:", "    appId: \(quote(bundle))"]
        case .terminate(let bundle):
            return bundle == appID ? ["- stopApp"] : ["- stopApp: \(quote(bundle))"]
        case .openURL(let url), .deepLink(let url):
            return ["- openLink: \(quote(url))"]
        case .tap(let x, let y):
            return ["- tapOn:", "    point: \(quote("\(Int(x.rounded())),\(Int(y.rounded()))"))"]
        case .swipe(let fromX, let fromY, let toX, let toY, let duration):
            return ["- swipe:",
                    "    start: \(quote("\(Int(fromX.rounded())),\(Int(fromY.rounded()))"))",
                    "    end: \(quote("\(Int(toX.rounded())),\(Int(toY.rounded()))"))",
                    "    duration: \(max(100, Int(duration * 1000)))"]
        case .type(let text):
            return ["- inputText: \(value(text, field: "text"))", "- hideKeyboard"]
        case .tapElement(let selector), .submit(let selector):
            return selectorCommand("tapOn", selector)
        case .doubleTap(let selector):
            return selectorCommand("doubleTapOn", selector)
        case .longPress(let selector, _):
            return selectorCommand("longPressOn", selector)
        case .typeElement(let selector, let text):
            // Regla de CuyScout: tras escribir se cierra el teclado.
            return selectorCommand("tapOn", selector) + ["- inputText: \(value(text, field: "text"))", "- hideKeyboard"]
        case .clearElement(let selector):
            return selectorCommand("tapOn", selector) + ["- eraseText"]
        case .waitFor(let selector, let timeout):
            guard let fields = selectorFields(selector) else { return unsupported(selector) }
            return ["- extendedWaitUntil:", "    visible:"] + fields.map { "        " + $0 } + ["    timeout: \(max(1000, Int(timeout * 1000)))"]
        case .assertVisible(let selector):
            return selectorCommand("assertVisible", selector)
        case .assertText(let selector, let expected):
            // Maestro comprueba el texto con el mismo selector: el elemento con ese id y ese texto.
            if selector.strategy == .accessibilityIdentifier {
                return ["- assertVisible:", "    id: \(quote(regexEscaped(selector.value)))", "    text: \(value(expected, field: "expected"))"]
            }
            return ["- assertVisible: \(value(expected, field: "expected"))"]
        case .scroll:
            return ["- scroll"]
        case .backgroundApp:
            return ["- pressKey: home"]
        case .sequence(let actions):
            return actions.enumerated().flatMap { commands(for: $0.element, path: "\(path).\($0.offset)", appID: appID, variables: &variables) }
        // Observaciones: no cambian la app.
        case .screenshot, .accessibilityTree, .accessibilityTreeWithOptions, .accessibilityDiff, .findElement, .findElements,
             .findElementFromElement, .findElementsFromElement, .elementAttribute, .elementDisplayed, .elementEnabled,
             .elementRect, .elementScreenshot, .elementSelected, .elementName, .elementProperty, .activeElement,
             .alertText, .listApps, .getClipboard, .getConfig, .enumerateFiles, .visualDiff:
            return []
        default:
            let kind = String(describing: action).prefix { $0 != "(" }
            return ["# Paso \(path): acción de CuyScout sin equivalente en Maestro (\(kind))."]
        }
    }

    private static func selectorCommand(_ command: String, _ selector: ScoutSelector) -> [String] {
        guard let fields = selectorFields(selector) else { return unsupported(selector) }
        // `- tapOn: "Texto"` es la forma corta de Maestro para seleccionar por texto.
        if fields.count == 1, fields[0].hasPrefix("text: ") { return ["- \(command): \(fields[0].dropFirst(6))"] }
        return ["- \(command):"] + fields.map { "    " + $0 }
    }

    /// Campos del selector de Maestro. Maestro trata `text` e `id` como expresiones regulares
    /// de la cadena completa: el valor literal se escapa.
    private static func selectorFields(_ selector: ScoutSelector) -> [String]? {
        switch selector.strategy {
        case .accessibilityIdentifier: return ["id: \(quote(regexEscaped(selector.value)))"]
        case .label, .value: return ["text: \(quote(regexEscaped(selector.value)))"]
        // Maestro compara el texto completo con una expresión regular: un prefijo o un fragmento se expresan con `.*`.
        case .labelStartsWith: return ["text: \(quote(regexEscaped(selector.value) + ".*"))"]
        case .labelContains: return ["text: \(quote(".*" + regexEscaped(selector.value) + ".*"))"]
        case .predicate, .type, .cssSelector, .xpath: return nil
        }
    }

    private static func unsupported(_ selector: ScoutSelector) -> [String] {
        ["# Selector \(selector.strategy.rawValue) sin equivalente en Maestro: \(selector.value.replacingOccurrences(of: "\n", with: " "))"]
    }

    static func regexEscaped(_ value: String) -> String {
        let special = Set("\\^$.|?*+()[]{}")
        return String(value.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }

    /// Cadena YAML entre comillas dobles.
    static func quote(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 { out += String(format: "\\x%02X", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}
