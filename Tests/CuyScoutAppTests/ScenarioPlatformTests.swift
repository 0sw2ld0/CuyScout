import XCTest
import CuyScoutCore
@testable import CuyScoutApp

/// Un escenario de Android se ejecuta como Android aunque el proyecto esté en iOS en ese momento (y al revés).
@MainActor
final class ScenarioPlatformTests: XCTestCase {
    private func artifact(platform: String, in root: URL, name: String = "t") throws -> URL {
        let url = root.appendingPathComponent("output/\(name).cuyscout.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["session": ["bundleIdentifier": "com.example", "device": ["platform": platform]]]).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return url
    }
    private func scenario(_ name: String, artifact: URL?) -> ProjectScenario { ProjectScenario(name: name, artifactURL: artifact, featureURL: nil, validationURL: nil, valuesURL: nil) }
    private func project(platform: Device.Platform, androidConfigured: Bool, iosConfigured: Bool) -> ScoutProject {
        ScoutProject(name: "P", directory: "/tmp/p", appPath: iosConfigured ? "/apps/App.app" : "", platform: platform,
                     android: androidConfigured ? AndroidProjectConfiguration(applicationId: "com.example") : nil)
    }
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("scenario-platform-\(UUID().uuidString)")

    func testAnAndroidRecordingRunsAsAndroidEvenWhenTheProjectIsOnIOS() throws {
        let android = try artifact(platform: "android", in: root)
        let p = project(platform: .ios, androidConfigured: true, iosConfigured: false)
        XCTAssertEqual(p.forScenario(scenario("t", artifact: android)).platform, .android)
        XCTAssertEqual(p.platform, .ios, "el proyecto no cambia: es una copia solo para esa ejecución")
    }

    func testTheScenarioSuffixWinsOverTheRecording() throws {
        let ios = try artifact(platform: "ios", in: root)
        let p = project(platform: .ios, androidConfigured: true, iosConfigured: true)
        XCTAssertEqual(p.forScenario(scenario("transferencia.android", artifact: ios)).platform, .android)
        let q = project(platform: .android, androidConfigured: true, iosConfigured: true)
        XCTAssertEqual(q.forScenario(scenario("transferencia.ios", artifact: nil)).platform, .ios)
    }

    func testItKeepsTheProjectPlatformWhenTheOtherOneIsNotConfiguredOrThereIsNoRecording() throws {
        let android = try artifact(platform: "android", in: root)
        let iosOnly = project(platform: .ios, androidConfigured: false, iosConfigured: true)
        XCTAssertEqual(iosOnly.forScenario(scenario("t", artifact: android)).platform, .ios, "sin app Android configurada no se cambia: el error será el de siempre")
        XCTAssertEqual(iosOnly.forScenario(scenario("solo-feature", artifact: nil)).platform, .ios)
        let both = project(platform: .android, androidConfigured: true, iosConfigured: true)
        XCTAssertEqual(both.forScenario(scenario("t", artifact: android)).platform, .android)
        XCTAssertTrue(both.isConfigured(for: .ios) && both.isConfigured(for: .android) && !iosOnly.isConfigured(for: .android))
    }

    func testAppiumCommandAlwaysCarriesThePlatformAndQuotesTheDevice() {
        XCTAssertEqual(AppiumCommand.run(scenario: "transferencia", platform: .android, deviceID: ""), "CUYSCOUT_PLATFORM=android scripts/replay-appium.sh transferencia")
        XCTAssertEqual(AppiumCommand.run(scenario: "t", platform: .android, deviceID: "9tlvcmpfln75zpeq"), "CUYSCOUT_PLATFORM=android CUYSCOUT_APPIUM_UDID=9tlvcmpfln75zpeq scripts/replay-appium.sh t")
        XCTAssertEqual(AppiumCommand.run(scenario: "mi escenario", platform: .ios, deviceID: "A B"), "CUYSCOUT_PLATFORM=ios CUYSCOUT_APPIUM_UDID='A B' scripts/replay-appium.sh 'mi escenario'")
        XCTAssertEqual(AppiumCommand.shellQuote("it's"), "'it'\\''s'")
    }

    /// El caso real: BMO-Demo está en iOS y su grabación es de Android. Solo si existe en esta Mac; no escribe nada.
    func testTheRealBMODemoAndroidRecordingNowPassesTheReplayValidation() throws {
        let dir = URL(fileURLWithPath: "/Users/oswaldoleon/Documents/cuycoders/workspace/BMO-Demo")
        let base = "transferencia-cuentas-propias-10-soles"
        let artifact = dir.appendingPathComponent("output/\(base).cuyscout.json")
        guard FileManager.default.fileExists(atPath: artifact.path) else { throw XCTSkip("Sin el proyecto BMO-Demo en esta Mac") }
        let suite = "cuyscout-real-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let project = try ScoutAppModel(defaults: defaults, detectSigningTeams: false).openProject(at: dir)
        let bundle = try JSONDecoder().decode(SessionArtifactBundle.self, from: Data(contentsOf: artifact))
        let item = scenario(base, artifact: artifact)
        guard project.platform == .ios, project.isConfigured(for: .android) else { throw XCTSkip("BMO-Demo no está en el estado que reproduce el caso (iOS con Android configurado)") }
        XCTAssertThrowsError(try project.validateReplayArtifact(bundle), "antes: «la plataforma de la grabación es Android y la del proyecto es iOS»")
        let scoped = project.forScenario(item)
        XCTAssertEqual(scoped.platform, .android)
        XCTAssertNoThrow(try scoped.validateReplayArtifact(bundle))
    }
}
