import SwiftUI

/// App host mínima del runner de CuyScout.
///
/// El target de UI tests necesita una TEST_TARGET app para compilar, pero el runner
/// nunca la usa: lanza la app bajo prueba con `XCUIApplication(bundleIdentifier:)`.
/// Así el runner se compila una sola vez, sin depender del código fuente de ninguna app.
@main
struct ScoutHostApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("CuyScout Runner")
                Text("Host de compilación — no interactúa con las pruebas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}