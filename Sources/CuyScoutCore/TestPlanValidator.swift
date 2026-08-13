import Foundation

public enum TestPlanValidator {
    public static func validate(_ plan: TestPlan, exports: [String] = []) -> TestPlanValidation {
        var errors: [String] = []
        var warnings = plan.warnings
        if plan.steps.isEmpty { errors.append("El plan no contiene pasos.") }
        for step in plan.steps where !step.success { errors.append("\(step.id): el paso terminó con error y requiere revisión.") }
        for (index, step) in plan.steps.enumerated() { inspect(step.action, path: "steps[\(index)]", errors: &errors, warnings: &warnings) }
        if !exports.isEmpty {
            for (index, export) in exports.enumerated() {
                if export.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("La exportación \(index) está vacía."); continue }
                if let issue = validateExport(export, index: index) { errors.append(issue) }
            }
        }
        let executable = plan.steps.allSatisfy(isExecutable)
        if !executable { warnings.append("El plan contiene acciones observacionales o no exportables que requieren revisión.") }
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
        case .findElement(let selector), .findElements(let selector), .tapElement(let selector), .waitFor(let selector, _), .assertVisible(let selector), .clearElement(let selector), .elementAttribute(let selector, _), .elementDisplayed(let selector), .elementEnabled(let selector), .elementRect(let selector), .elementScreenshot(let selector):
            inspectSelector(selector, path: path, errors: &errors, warnings: &warnings)
        default: break
        }
    }

    private static func inspectSelector(_ selector: ScoutSelector, path: String, errors: inout [String], warnings: inout [String]) {
        if selector.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("\(path): el selector está vacío.") }
        if selector.strategy == .label || selector.strategy == .value { warnings.append("\(path): el selector usa \(selector.strategy.rawValue), que puede cambiar con el contenido; prefiere accessibilityIdentifier.") }
    }

    private static func inspectText(_ text: String, path: String, errors: inout [String], warnings: inout [String]) {
        if text.isEmpty { errors.append("\(path): el texto de entrada está vacío.") }
        if text == "<text>" || text == "<redacted>" { warnings.append("\(path): contiene un placeholder de dato sensible; parametrízalo antes de ejecutar.") }
        if text.lowercased().contains("password") || text.lowercased().contains("secret") || text.lowercased().contains("token") { warnings.append("\(path): revisa que el dato sensible se exporte como variable segura.") }
    }

    private static func isExecutable(_ step: TestPlanStep) -> Bool {
        switch step.action {
        case .launch, .terminate, .backgroundApp, .openURL, .navigateBack, .navigateForward, .refresh, .acceptAlert, .dismissAlert, .rotate, .getClipboard, .setClipboard, .tap, .swipe, .type, .tapElement, .typeElement, .waitFor, .assertVisible, .assertText, .clearElement: return true
        default: return false
        }
    }

    private static func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }

    private static func validateExport(_ value: String, index: Int) -> String? {
        let required: [Int: [String]] = [
            0: ["XCTestCase", "func test"],
            1: ["webdriverio", "describe("],
            2: ["WebdriverIO.Browser", "WebdriverIO.Element", "describe("],
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
