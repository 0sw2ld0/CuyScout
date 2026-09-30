import XCTest
@testable import CuyScoutCore

final class InstalledAppsTests: XCTestCase {
    func testParsesUserAppsFromDevicectl() {
        let json = #"""
        {"result": {"apps": [
          {"name": "Demo Wallet", "bundleIdentifier": "com.example.wallet.dev", "version": "1.0.0", "builtByDeveloper": true, "hidden": false, "appClip": false},
          {"name": "Tienda", "bundleIdentifier": "com.example.store", "version": "2", "builtByDeveloper": false},
          {"name": "Oculta", "bundleIdentifier": "com.example.hidden", "hidden": true},
          {"name": "Clip", "bundleIdentifier": "com.example.clip", "appClip": true}
        ]}}
        """#
        let apps = SimulatorController.physicalApps(from: Data(json.utf8))
        XCTAssertEqual(apps.map(\.bundleIdentifier), ["com.example.wallet.dev", "com.example.store"])
        XCTAssertEqual(apps.first?.developerBuild, true)
        XCTAssertEqual(apps.last?.developerBuild, false)
    }

    func testParsesOnlyUserAppsFromSimctlListapps() {
        let plist = #"""
        {
            "com.apple.Preferences" = { ApplicationType = System; CFBundleDisplayName = Settings; };
            "com.example.app" = { ApplicationType = User; CFBundleDisplayName = "Mi App"; CFBundleShortVersionString = "1.2"; };
        }
        """#
        let apps = SimulatorController.simulatorApps(from: Data(plist.utf8))
        XCTAssertEqual(apps, [InstalledApp(bundleIdentifier: "com.example.app", name: "Mi App", version: "1.2", developerBuild: true)])
    }

    func testOpenSessionScriptCanUseAnInstalledApp() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let script = try XCTUnwrap(ProjectScaffolder.files(for: options)["scripts/open-session.sh"])
        XCTAssertTrue(script.contains("physicalBundleId"))
        XCTAssertTrue(script.contains("CUYSCOUT_BUNDLE_ID"))
        XCTAssertTrue(script.contains(#"caps["appium:bundleId"]"#))
        XCTAssertTrue(ProjectScaffolder.agentsMarkdownBlock(for: options).contains("`physicalBundleId`"))
    }

    func testReplayScriptAcceptsAnInstalledAppWithoutInstaller() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "", cuyscoutRepoPath: "")
        let script = try XCTUnwrap(ProjectScaffolder.files(for: options)["scripts/replay-cuyscout.sh"])
        XCTAssertTrue(script.contains(#"PROJECT_BUNDLE_ID="$(python3"#))
        XCTAssertTrue(script.contains("se reproduce sin reinstalarla"))
        XCTAssertTrue(script.contains("CUYSCOUT_BUNDLE_ID"))
    }
}
