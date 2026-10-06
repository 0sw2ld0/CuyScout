import CoreGraphics
import ImageIO
import XCTest
@testable import CuyScoutCore

final class IdentifierBacklogTests: XCTestCase {
    private var project: URL!
    override func setUp() { project = FileManager.default.temporaryDirectory.appendingPathComponent("idbacklog-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: project) }

    private func element(_ type: String, id: String = "", label: String = "", _ x: Double, _ y: Double, _ w: Double = 370, _ h: Double = 48) -> [String: Any] {
        ["type": type, "identifier": id, "label": label, "frame": ["x": x, "y": y, "width": w, "height": h]]
    }
    private func welcome(buttonID: String = "") -> [[String: Any]] {
        [element("application", label: "Demo", 0, 0, 402, 874),
         element("navigationBar", label: "Ingresar a la app", 0, 60, 402, 44),
         element("staticText", label: "Hola, Persona Ejemplo", 40, 300, 320, 30),
         element("button", id: "btn_face", label: "Ingresar con Face ID", 16, 700),
         element("button", id: buttonID, label: "Ingresar con clave web", 16, 776),
         element("button", 350, 70, 30, 30),
         element("cell", id: "row", label: "Uno", 0, 400, 402, 44),
         element("cell", id: "row", label: "Dos", 0, 444, 402, 44)]
    }

    func testFindsMissingUnlabeledAndDuplicateIdentifiersPerScreen() throws {
        let store = IdentifierBacklogStore(projectDirectory: project)
        let result = store.observe(elements: welcome(), sessionID: "s1")
        XCTAssertEqual(result.screenKey, "ingresar-a-la-app")
        XCTAssertTrue(result.needsScreenshot)
        let findings = Array(store.snapshot.findings.values)
        XCTAssertEqual(findings.first { $0.kind == .missingIdentifier }?.label, "Ingresar con clave web")
        XCTAssertNotNil(findings.first { $0.kind == .noTextNoIdentifier && $0.type == "button" })
        XCTAssertEqual(findings.first { $0.kind == .duplicateIdentifier }?.identifier, "row")
        XCTAssertFalse(findings.contains { $0.label == "Ingresar con Face ID" }, "ya tiene identificador")
        XCTAssertEqual(store.snapshot.screens["ingresar-a-la-app"]?.title, "Ingresar a la app")
        store.save()
        XCTAssertEqual(IdentifierBacklogStore(projectDirectory: project).snapshot.findings.count, findings.count, "se guarda por proyecto")
    }

    func testAnElementUsedByATestIsHighPriorityAndResolvesOnceItGetsAnIdentifier() {
        let store = IdentifierBacklogStore(projectDirectory: project)
        let elements = welcome()
        store.observe(elements: elements, sessionID: "s1")
        store.markUsed(element: elements[4], elements: elements, sessionID: "s1", how: "coordenadas")
        let used = store.snapshot.findings.values.first { $0.label == "Ingresar con clave web" }
        XCTAssertEqual(used?.isHighPriority, true)
        XCTAssertEqual(used?.usedBy, ["s1": "coordenadas"])
        store.observe(elements: welcome(buttonID: "btn_clave_web"), sessionID: "s2")
        let resolved = store.snapshot.findings.values.first { $0.label == "Ingresar con clave web" }
        XCTAssertEqual(resolved?.status, .resolved)
        XCTAssertEqual(resolved?.resolvedIdentifier, "btn_clave_web")
    }

    func testATextThatChangesInTheSamePlaceIsReportedAsChangingText() {
        let store = IdentifierBacklogStore(projectDirectory: project)
        let base = [element("navigationBar", label: "Clave", 0, 60, 402, 44)]
        store.observe(elements: base + [element("secureTextField", label: "Clave, cuadro de texto, 0 de 6", 16, 300)], sessionID: "s")
        store.observe(elements: base + [element("secureTextField", label: "Clave, cuadro de texto, 2 de 6", 16, 300)], sessionID: "s")
        let findings = store.snapshot.findings.values.filter { $0.type == "secureTextField" }
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.kind, .changingText)
    }

    func testSharedTextsHideNamesNumbersAndEmails() {
        XCTAssertEqual(IdentifierBacklogStore.redact("Hola, Persona Ejemplo"), "Hola, <nombre>")
        XCTAssertFalse(IdentifierBacklogStore.redact("Cuenta Corriente ****1234").contains("1234"))
        XCTAssertFalse(IdentifierBacklogStore.redact("Escríbenos a persona@example.com").contains("persona@example.com"))
        XCTAssertEqual(IdentifierBacklogStore.redact("Ingresar con clave web"), "Ingresar con clave web")
    }

    func testSuggestsIdentifiersWithTheAppConvention() {
        func finding(_ type: String, _ label: String, frame: [Double] = [16, 776, 370, 48]) -> IdentifierFinding {
            IdentifierFinding(key: "k", kind: label.isEmpty ? .noTextNoIdentifier : .missingIdentifier, screenKey: "bienvenida", screen: "Bienvenida", type: type, label: label, identifier: nil,
                              frame: frame, usedBy: [:], timesSeen: 1, firstSeen: Date(), lastSeen: Date(), status: .pending, resolvedIdentifier: nil)
        }
        XCTAssertEqual(IdentifierReport.suggestedIdentifier(for: finding("button", "Ingresar con clave web"), known: ["btn_login", "input_amount"]), "btn_ingresar_clave_web")
        XCTAssertEqual(IdentifierReport.suggestedIdentifier(for: finding("textField", "Monto"), known: ["btn_login", "input_amount"]), "input_monto")
        XCTAssertEqual(IdentifierReport.suggestedIdentifier(for: finding("button", "", frame: [350, 70, 30, 30]), known: []), "btn_bienvenida_arriba_derecha")
        XCTAssertEqual(IdentifierReport.suggestedIdentifier(for: finding("button", "Continuar"), known: ["loginButton", "amountField", "sendButton"]), "continuarButton")
    }

    func testReportsInHTMLMarkdownAndCSVWithCropsAndRecordedSteps() throws {
        let store = IdentifierBacklogStore(projectDirectory: project)
        let elements = welcome()
        let screen = store.observe(elements: elements, sessionID: "sess-1")
        store.saveScreenshot(try screenshot(width: 1206, height: 2622), screenKey: screen.screenKey)
        store.markUsed(element: elements[4], elements: elements, sessionID: "sess-1", how: "texto")
        store.save()
        // Grabación existente que usa un texto y unas coordenadas.
        let output = project.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let artifact: [String: Any] = ["session": ["id": "sess-1"], "recording": ["steps": [
            ["success": true, "action": ["type": "tap", "x": 201.0, "y": 800.0]],
            ["success": true, "action": ["type": "tapElement", "selector": ["strategy": "label", "value": "=HYPERLINK(\"x\")"]]]]]]
        try JSONSerialization.data(withJSONObject: artifact).write(to: output.appendingPathComponent("login.cuyscout.json"))

        let result = try IdentifierReport.write(projectDirectory: project, projectName: "Demo")
        let html = try String(contentsOf: result.html, encoding: .utf8)
        let markdown = try String(contentsOf: result.markdown, encoding: .utf8)
        let csv = try String(contentsOf: result.csv, encoding: .utf8)
        XCTAssertTrue(html.contains("data:image/png;base64,"), "recorte del elemento en su pantalla")
        XCTAssertTrue(html.contains("Prioridad alta"))
        XCTAssertTrue(markdown.contains("| Pendientes | Prioridad alta |"))
        XCTAssertTrue(markdown.contains("`btn_ingresar_clave_web`"))
        XCTAssertTrue(markdown.contains("login"), "escenario que lo usa")
        XCTAssertTrue(csv.hasPrefix("estado,prioridad,problema,pantalla"))
        XCTAssertTrue(csv.contains("'=HYPERLINK"), "una celda con fórmula se neutraliza")
        XCTAssertTrue(csv.contains("toque en (201, 800)"))
        XCTAssertFalse(html.contains("Persona Ejemplo"))
        XCTAssertGreaterThan(result.highPriority, 0)
        XCTAssertEqual(try String(contentsOf: store.directory.appendingPathComponent(".gitignore"), encoding: .utf8), "pantallas/\n")
    }

    private func screenshot(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
