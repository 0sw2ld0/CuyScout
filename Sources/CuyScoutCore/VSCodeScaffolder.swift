import Foundation

/// Configuración opcional para trabajar el proyecto de pruebas en Visual Studio Code:
/// - `.github/prompts/*.prompt.md`: prompts de Copilot (`/nuevo-escenario`, `/ejecutar-escenario`)
///   que remiten a AGENTS.md. Son de CuyScout y se regeneran.
/// - `.vscode/extensions.json` y `.vscode/settings.json`: se **fusionan** (solo se agregan
///   claves que falten); nunca se pisa lo que el equipo ya configuró. Si el archivo tiene
///   comentarios (JSONC) y no se puede leer como JSON, se deja intacto y se avisa.
public enum VSCodeScaffolder {
    public static let recommendedExtensions = ["CucumberOpen.cucumber-official", "GitHub.copilot-chat"]

    /// Ajustes para escribir `.feature` con formato consistente y que Copilot lea AGENTS.md.
    public static var settings: [String: Any] { [
        "[cucumber]": [
            "editor.defaultFormatter": "CucumberOpen.cucumber-official",
            "editor.formatOnSave": true,
            "editor.tabSize": 2,
            "editor.insertSpaces": true
        ],
        "cucumber.features": ["features/**/*.feature"],
        "files.trimTrailingWhitespace": true,
        "files.insertFinalNewline": true,
        "chat.useAgentsMdFile": true,
        "chat.promptFiles": true,
        "github.copilot.chat.codeGeneration.useInstructionFiles": true
    ] }

    public static func promptFiles() -> [String: String] {
        [
            ".github/prompts/nuevo-escenario.prompt.md": #"""
            ---
            mode: agent
            description: Crea un escenario Gherkin en features/ a partir de una descripción de negocio, listo para CuyScout
            ---
            Crea una prueba nueva para este proyecto a partir de esta descripción:

            ${input:descripcion:Qué debe probar, con sus valores (p. ej. pagar el servicio X con el código 123 y el monto 85.50)}

            1. Lee la sección «Escribir un escenario (`features/`)» de [AGENTS.md](../../AGENTS.md) y cúmplela al pie de la letra.
            2. Revisa `features/` para reutilizar el mismo estilo, `Background` y alias. Si ya existe un escenario igual o muy parecido, dímelo y no crees otro.
            3. De `fixtures/credentials.test.json` usa solo los **nombres** de los alias; nunca copies correos, contraseñas ni otros datos al `.feature`. Si falta el alias necesario, detente y pídelo.
            4. Si la descripción no da un valor que la prueba necesita (cuenta, monto, servicio, código…), pregúntalo antes de escribir; no lo inventes.
            5. Crea `features/<nombre-en-kebab>.feature` con un solo `Scenario`, en español y solo en lenguaje de negocio: sin selectores, coordenadas ni esperas.
            6. No ejecutes la prueba ni abras sesiones de CuyScout. Termina mostrando la ruta del archivo, los valores explícitos y las verificaciones que incluiste, para que lo revise.

            """#,
            ".github/prompts/ejecutar-escenario.prompt.md": #"""
            ---
            mode: agent
            description: Genera o reproduce con CuyScout un escenario de features/
            ---
            Ejecuta el escenario `${input:escenario:nombre del .feature sin extensión, p. ej. transferencia-propia}` siguiendo [AGENTS.md](../../AGENTS.md):

            - Si existe `output/<escenario>.cuyscout.json` y el `.feature` no cambió desde entonces, usa el modo «reproducir con CuyScout» (`scripts/replay-cuyscout.sh <escenario>`).
            - Si no, usa el modo «generar»: una sola sesión, `observe` antes de cada decisión, verifica en pantalla antes de cualquier acción irreversible y cierra con `scripts/close-session.sh`.
            - Antes de empezar lee `rules/*.md`: es lo que ya se aprendió de esta app. Alcanza los `Given` por tu cuenta según «Alcanzar las precondiciones» de AGENTS.md.
            - Abre la sesión solo con `scripts/open-session.sh` (sin variables delante: elige driver y app del proyecto). Si hay una sesión con `leaseExpired: true`, ignórala.
            - Resuelve credenciales solo desde `fixtures/credentials.test.json` por alias; no las muestres en el chat.
            - Ante un error de CuyScout, sigue su `hint` y la tabla «Errores de CuyScout y qué hacer»; no busques en el código de CuyScout.
            - Si resolviste un obstáculo nuevo, guárdalo como regla del proyecto (`POST /lessons` con `scope: "project"`), sin datos sensibles.
            - Si no llegaste a probar el escenario (servicio caído, precondición imposible), cierra con `scripts/close-session.sh "$SESSION" <escenario> --discard --reason <motivo> --step "<paso>"`; nunca con `curl -X DELETE`.

            Al final, reporta el resultado, la evidencia que se vio en pantalla y los archivos que quedaron en `output/`. Si algo falla, detente y explica en qué paso; no reintentes a ciegas una acción irreversible.

            """#
        ]
    }

    /// `settings.json` con las claves que falten, o nil si el existente no se puede leer.
    public static func mergedSettings(existing: String?) -> String? {
        merge(existing: existing) { current in
            var result = current
            for (key, value) in settings {
                if let defaults = value as? [String: Any] {
                    var nested = result[key] as? [String: Any] ?? [:]
                    for (inner, innerValue) in defaults where nested[inner] == nil { nested[inner] = innerValue }
                    result[key] = nested
                } else if result[key] == nil {
                    result[key] = value
                }
            }
            return result
        }
    }

    /// `extensions.json` con las recomendaciones de CuyScout añadidas, o nil si no se puede leer.
    public static func mergedExtensions(existing: String?) -> String? {
        merge(existing: existing) { current in
            var result = current
            var recommendations = current["recommendations"] as? [String] ?? []
            for id in recommendedExtensions where !recommendations.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) { recommendations.append(id) }
            result["recommendations"] = recommendations
            return result
        }
    }

    /// Escribe la configuración en `root` y devuelve una línea por archivo para el informe.
    @discardableResult
    public static func apply(to root: URL) throws -> [String] {
        let fileManager = FileManager.default
        var report: [String] = []
        for (path, content) in promptFiles().sorted(by: { $0.key < $1.key }) {
            let url = root.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            report.append("\(path) (regenerado)")
        }
        for (path, mergeFunction) in [(".vscode/settings.json", mergedSettings), (".vscode/extensions.json", mergedExtensions)] {
            let url = root.appendingPathComponent(path)
            let existing = try? String(contentsOf: url, encoding: .utf8)
            guard let merged = mergeFunction(existing) else {
                report.append("\(path) (tiene comentarios o no es JSON válido; no se tocó — revísalo a mano)")
                continue
            }
            if merged == existing { report.append("\(path) (ya estaba configurado)"); continue }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try merged.write(to: url, atomically: true, encoding: .utf8)
            report.append("\(path) (\(existing == nil ? "creado" : "actualizado sin quitar lo existente"))")
        }
        return report
    }

    private static func merge(existing: String?, _ transform: ([String: Any]) -> [String: Any]) -> String? {
        var current: [String: Any] = [:]
        if let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = (try? JSONSerialization.jsonObject(with: Data(existing.utf8))) as? [String: Any] else { return nil }
            current = parsed
        }
        let result = transform(current)
        if let existing, let parsed = (try? JSONSerialization.jsonObject(with: Data(existing.utf8))) as? NSDictionary, parsed.isEqual(to: result) { return existing }
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text + "\n"
    }
}
