import AppKit
import SwiftUI
import XCTest
import CuyScoutCore
@testable import CuyScoutApp

/// Las vistas de fragmentos, credenciales y escenarios se renderizan de verdad (ventana sin mostrar) y leen el proyecto.
@MainActor
final class ProjectAuthoringViewsTests: XCTestCase {
    private func makeProject() throws -> (ScoutProject, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("authoring-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("{\"platform\":\"android\"}".utf8).write(to: root.appendingPathComponent(ProjectUpdater.configFile))
        try Data("# agentes".utf8).write(to: root.appendingPathComponent("AGENTS.md"))
        try Data("#!/bin/sh\n".utf8).write(to: root.appendingPathComponent("scripts/open-session.sh"))
        let suite = "cuyscout-authoring-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = ScoutAppModel(defaults: defaults, detectSigningTeams: false)
        return (try model.openProject(at: root), root)
    }

    /// Dibuja la vista real en una ventana sin mostrar. Devuelve el tamaño que pide su contenido y una imagen del resultado.
    private func render<V: View>(_ view: V, size: NSSize = NSSize(width: 720, height: 640)) -> (fitting: NSSize, image: NSBitmapImageRep?) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        if let image { host.cacheDisplay(in: host.bounds, to: image) }
        let fitting = host.fittingSize
        window.contentView = nil
        return (fitting, image)
    }
    private func assertRenders<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = render(view)
        // Con CUYSCOUT_UI_SNAPSHOT_DIR se guarda una imagen de cada vista, para revisarlas a ojo.
        if let directory = ProcessInfo.processInfo.environment["CUYSCOUT_UI_SNAPSHOT_DIR"], let png = result.image?.representation(using: .png, properties: [:]) {
            let file = URL(fileURLWithPath: directory).appendingPathComponent(name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "") + ".png")
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: file)
        }
        XCTAssertGreaterThan(result.fitting.width, 100, "\(name) no tiene contenido", file: file, line: line)
        XCTAssertGreaterThan(result.fitting.height, 100, "\(name) no tiene contenido", file: file, line: line)
        XCTAssertNotNil(result.image, "\(name) no se dibujó", file: file, line: line)
    }

    func testFragmentsViewRendersEmptyAndWithFragments() throws {
        let (project, root) = try makeProject()
        assertRenders(FragmentsView(project: project), "Fragmentos (vacío)")
        let check = SessionFragment.Check(selector: .init(strategy: .label, value: "Transferir"))
        try FragmentStore.save(SessionFragment(name: "login", platform: .android, bundleIdentifier: "com.example", defaultAlias: "demo_user",
                                               variables: ["1.text": "password_android"], exitCheck: check, skipIfAlreadyDone: true,
                                               steps: [.tapElement(.init(strategy: .label, value: "Ingresar")), .typeElement(.init(strategy: .label, value: "Clave"), text: "<redacted>")]), in: root, overwrite: false)
        assertRenders(FragmentsView(project: project), "Fragmentos (con login)")
        XCTAssertEqual(FragmentStore.list(in: project.url).map(\.name), ["login"], "la vista lee fragments/ del proyecto")
    }

    func testCredentialsViewRendersAndNeverWritesWhatItDidNotChange() throws {
        let (project, root) = try makeProject()
        try CredentialsStore.save(["demo_user": ["password_android": "valor-muy-secreto"]], in: root)
        let before = try Data(contentsOf: CredentialsStore.url(in: root))
        assertRenders(CredentialsView(project: project), "Credenciales")
        XCTAssertEqual(try Data(contentsOf: CredentialsStore.url(in: root)), before, "abrir la vista no modifica el archivo")
        try CredentialsStore.addToGitIgnore(in: root)
        assertRenders(CredentialsView(project: project), "Credenciales (ignoradas por git)")
    }

    func testCredentialsViewRendersForAFileItDoesNotUnderstand() throws {
        let (project, root) = try makeProject()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        let odd = #"{"demo_user":{"password":"x","reintentos":3}}"#
        try Data(odd.utf8).write(to: CredentialsStore.url(in: root))
        assertRenders(CredentialsView(project: project), "Credenciales (archivo no soportado)")
        XCTAssertEqual(try String(contentsOf: CredentialsStore.url(in: root), encoding: .utf8), odd)
    }

    func testFeatureEditorRendersForANewAndAnExistingScenario() throws {
        let (project, root) = try makeProject()
        let check = SessionFragment.Check(selector: .init(strategy: .label, value: "Transferir"))
        try FragmentStore.save(SessionFragment(name: "login", platform: .android, bundleIdentifier: nil, defaultAlias: nil, variables: [:], exitCheck: check, skipIfAlreadyDone: true, steps: []), in: root, overwrite: false)
        assertRenders(FeatureEditorView(project: project, mode: .new), "Nuevo escenario")
        let original = "@fragment:login\nFeature: Transferencia\n  Scenario: Propia\n    When toco Transferir\n"
        try FeatureFile.save(original, name: "transferencia", in: root, overwrite: false)
        assertRenders(FeatureEditorView(project: project, mode: .edit(name: "transferencia")), "Editar escenario")
        XCTAssertEqual(try String(contentsOf: FeatureFile.url(name: "transferencia", in: root), encoding: .utf8), original, "abrir el editor no cambia el archivo")
        XCTAssertEqual(FeatureFile.fragment(in: original), "login")
    }
}
