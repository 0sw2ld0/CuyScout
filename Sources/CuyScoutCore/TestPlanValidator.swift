import Foundation

public enum TestPlanValidator {
    public static func validate(_ plan: TestPlan, exports: [String] = []) -> TestPlanValidation {
        var errors: [String] = []
        var warnings = plan.warnings
        if plan.steps.isEmpty { errors.append("El plan no contiene pasos.") }
        for step in plan.steps where !step.success {
            // Una lectura que falló (p. ej. el árbol durante una transición) no cambió nada: es ruido de exploración
            // que el replay no repite. Un paso que actúa y falló sí invalida el plan.
            if isObservational(step.action) { warnings.append("\(step.id): lectura fallida durante la exploración; no se reproduce.") }
            else { errors.append("\(step.id): el paso terminó con error y requiere revisión.") }
        }
        for (index, step) in plan.steps.enumerated() { inspect(step.action, path: "steps[\(index)]", errors: &errors, warnings: &warnings) }
        if !exports.isEmpty {
            for (index, export) in exports.enumerated() {
                if export.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("La exportación \(index) está vacía."); continue }
                if let issue = validateExport(export, index: index) { errors.append(issue) }
            }
        }
        // Las lecturas (árbol, atributos, capturas…) no se exportan ni cambian el estado: no impiden que el plan sea ejecutable.
        let executable = plan.steps.filter { !isObservational($0.action) }.allSatisfy { isExecutable($0.action) }
        if !executable { warnings.append("El plan contiene acciones no exportables que requieren revisión.") }
        return TestPlanValidation(valid: errors.isEmpty, executable: errors.isEmpty && executable, errors: errors, warnings: unique(warnings))
    }

    private static func inspect(_ action: ScoutAction, path: String, errors: inout [String], warnings: inout [String]) {
        switch action {
        case .sequence(let actions):
            if actions.isEmpty { errors.append("\(path): la secuencia está vacía.") }
            for (index, child) in actions.enumerated() { inspect(child, path: "\(path).actions[\(index)]", errors: &errors, warnings: &warnings) }
        case .tap, .swipe:
            warnings.append("\(path): usa coordenadas; prefiere un selector semántico para que la prueba sea estable.")
        case .type(let text), .setClipboard(let text):
            inspectText(text, path: path, errors: &errors, warnings: &warnings)
        case .typeElement(let selector, let text):
            inspectSelector(selector, path: path, errors: &errors, warnings: &warnings)
            inspectText(text, path: path, errors: &errors, warnings: &warnings)
        case .assertText(let selector, let expected):
            inspectSelector(selector, path: path, errors: &errors, warnings: &warnings)
            if expected.isEmpty { errors.append("\(path): la assertion no puede estar vacía.") }
            if expected == "<text>" || expected == "<redacted>" { warnings.append("\(path): la assertion contiene un placeholder y debe parametrizarse.") }
        case .runFragment(let name, _):
            warnings.append("\(path): el fragmento «\(name)» lo expande el gateway: sirve en el replay de CuyScout, pero no se exporta a Appium/XCTest/Maestro.")
        case .findElement(let selector), .findElements(let selector), .tapElement(let selector), .waitFor(let selector, _), .assertVisible(let selector), .clearElement(let selector), .elementAttribute(let selector, _), .elementDisplayed(let selector), .elementEnabled(let selector), .elementRect(let selector), .elementScreenshot(let selector):
            inspectSelector(selector, path: path, errors: &errors, warnings: &warnings)
        default: break
        }
    }

    private static func inspectSelector(_ selector: ScoutSelector, path: String, errors: inout [String], warnings: inout [String]) {
        if selector.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("\(path): el selector está vacío.") }
        if selector.strategy == .labelStartsWith || selector.strategy == .labelContains {
            warnings.append("\(path): el selector \(selector.strategy.rawValue) lo resuelve el gateway: sirve en el replay de CuyScout y en Maestro, pero no se exporta a Appium/XCTest.")
        }
        if selector.strategy == .label || selector.strategy == .value { warnings.append("\(path): el selector usa \(selector.strategy.rawValue), que puede cambiar con el contenido; prefiere accessibilityIdentifier.") }
    }

    private static func inspectText(_ text: String, path: String, errors: inout [String], warnings: inout [String]) {
        if text.isEmpty { errors.append("\(path): el texto de entrada está vacío.") }
        if text == "<text>" || text == "<redacted>" { warnings.append("\(path): contiene un placeholder de dato sensible; parametrízalo antes de ejecutar.") }
        if text.lowercased().contains("password") || text.lowercased().contains("secret") || text.lowercased().contains("token") { warnings.append("\(path): revisa que el dato sensible se exporte como variable segura.") }
    }

    /// Acciones que solo leen la pantalla o el dispositivo.
    static func isObservational(_ action: ScoutAction) -> Bool {
        switch action {
        case .accessibilityTree, .accessibilityTreeWithOptions, .accessibilityDiff, .screenshot, .screenStatic, .visualDiff,
             .elementAttribute, .elementProperty, .elementDisplayed, .elementEnabled, .elementRect, .elementSelected, .elementName,
             .elementScreenshot, .findElement, .findElements, .findElementFromElement, .findElementsFromElement, .alertText,
             .activeElement, .listApps, .getClipboard:
            return true
        default:
            return false
        }
    }

    private static func isExecutable(_ action: ScoutAction) -> Bool {
        switch action {
        case .sequence(let actions): return !actions.isEmpty && actions.allSatisfy(isExecutable)
        case .runFragment: return true
        case .launch, .terminate, .backgroundApp, .openURL, .navigateBack, .navigateForward, .refresh, .acceptAlert, .dismissAlert, .rotate, .getClipboard, .setClipboard, .tap, .swipe, .type, .tapElement, .typeElement, .waitFor, .assertVisible, .assertText, .clearElement: return true
        default: return false
        }
    }

    private static func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }

    private static func validateExport(_ value: String, index: Int) -> String? {
        let required: [Int: [String]] = [
            0: ["XCTestCase", "func test"],
            1: ["webdriverio", "describe("],
            // TypeScript is a standalone runner, not a Mocha suite.
            2: ["WebdriverIO.Browser", "WebdriverIO.Element", "async function main(): Promise<void>", "preflight(actions);", "main().catch("],
            3: ["unittest", "def test_recorded_exploration"],
            4: ["@Test", "class"],
            5: ["Feature:", "Scenario:"],
            6: []
        ]
        if index == 6 {
            guard let data = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data), object is [[String: Any]] else { return "La exportación JSON portable no contiene un array válido." }
            return nil
        }
        guard let markers = required[index], let missing = markers.first(where: { !value.contains($0) }) else { return nil }
        return "La exportación \(index) no contiene el marcador estructural requerido: \(missing)."
    }
}
