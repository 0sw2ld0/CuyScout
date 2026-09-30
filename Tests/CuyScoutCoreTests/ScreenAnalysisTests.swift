import CoreGraphics
import ImageIO
import XCTest
@testable import CuyScoutCore

final class ScreenAnalysisTests: XCTestCase {
    /// PNG de 390×844 con fondo `gray` y, opcionalmente, barra de estado y contenido dibujados.
    private func png(gray: CGFloat, statusBar: Bool = false, content: Bool = false) throws -> Data {
        let width = 390, height = 844
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: gray, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ink = CGColor(gray: gray > 0.5 ? 0 : 1, alpha: 1)
        context.setFillColor(ink)
        // En CoreGraphics y = 0 es abajo: la barra de estado queda en la parte alta.
        if statusBar { context.fill(CGRect(x: 20, y: height - 40, width: 60, height: 18)); context.fill(CGRect(x: 300, y: height - 40, width: 60, height: 18)) }
        if content {
            context.fill(CGRect(x: 40, y: 300, width: 310, height: 56))
            for row in 0..<6 { context.fill(CGRect(x: 40, y: 450 + row * 40, width: 200 + row * 10, height: 14)) }
        }
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testBlackOrUniformScreensAreBlank() throws {
        XCTAssertTrue(ScreenAnalysis.isBlank(png: try png(gray: 0)))
        XCTAssertTrue(ScreenAnalysis.isBlank(png: try png(gray: 1)))
        XCTAssertTrue(ScreenAnalysis.isBlank(png: try png(gray: 0, statusBar: true)), "la hora y la batería no cuentan como contenido")
    }

    func testScreensWithContentAreNotBlank() throws {
        XCTAssertFalse(ScreenAnalysis.isBlank(png: try png(gray: 1, content: true)))
        XCTAssertFalse(ScreenAnalysis.isBlank(png: try png(gray: 0, statusBar: true, content: true)))
        XCTAssertFalse(ScreenAnalysis.isBlank(png: Data("no es png".utf8)), "sin captura no se afirma nada")
    }

    func testAgentsAndOpenSessionKnowTheBlankScreen() throws {
        let options = ProjectScaffolder.Options(appName: "Demo", appPath: "/tmp/Demo.app", cuyscoutRepoPath: "")
        let agents = ProjectScaffolder.agentsMarkdownBlock(for: options)
        XCTAssertTrue(agents.contains("`app_screen_blank`"))
        XCTAssertTrue(agents.contains("--reason fallo_app"))
        let script = try XCTUnwrap(ProjectScaffolder.files(for: options)["scripts/open-session.sh"])
        XCTAssertTrue(script.contains(#""app_screen_blank" in blockers"#))
    }

    func testReadinessCarriesHowLongTheUIHasBeenLoading() throws {
        let readiness = SessionReadiness(interactionReady: false, context: "NATIVE_APP", xctestBridgeConnected: true, webViewConnected: false,
                                         blockers: ["app_ui_loading", "app_screen_blank"], uiLoadingSeconds: 25)
        let decoded = try JSONDecoder().decode(SessionReadiness.self, from: JSONEncoder().encode(readiness))
        XCTAssertEqual(decoded.uiLoadingSeconds, 25)
        let legacy = try JSONDecoder().decode(SessionReadiness.self, from: Data(#"{"interactionReady":true,"context":"NATIVE_APP","xctestBridgeConnected":true,"webViewConnected":false,"commandsUsed":0,"blockers":[]}"#.utf8))
        XCTAssertNil(legacy.uiLoadingSeconds)
    }
}
