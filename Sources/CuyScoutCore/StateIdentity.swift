import Foundation
import CryptoKit

/// Identidad compacta de una pantalla, estable frente a lo que cambia entre dos
/// observaciones de la *misma* pantalla y sensible a lo que la convierte en otra.
///
/// De esto dependen `changed`, la detección de bucles, la cobertura de exploración y el
/// grafo de navegación: si dos pantallas distintas comparten identidad el agente cree que
/// no avanzó, y si la misma pantalla cambia de identidad en cada lectura cree que avanza
/// mientras da vueltas.
public enum StateIdentity {
    public static func stableID(_ source: String) -> String {
        // El árbol nativo llega como JSON serializado: sin orden garantizado de claves y con
        // geometría que se mueve durante las animaciones. La identidad se toma del contenido
        // semántico —qué controles hay, cómo se llaman y qué contienen—, no del texto crudo.
        //
        // La firma se extrae ANTES de depurar valores dinámicos: la depuración opera sobre
        // texto y rompería el JSON (un frame como 1240.6666666666667 tiene trece dígitos
        // seguidos y la regex de contadores lo dejaría en `1240.<dynamic>`, ya no parseable).
        let canonical = semanticSignature(of: source) ?? source
        let normalized = scrubbingDynamicValues(canonical)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return "state:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func scrubbingDynamicValues(_ source: String) -> String {
        var normalized = source
        let patterns = [
            #"\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?\b"#,
            #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"#,
            #"\b\d{10,}\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            normalized = regex.stringByReplacingMatches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized), withTemplate: "<dynamic>")
        }
        return normalized.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// Firma semántica del árbol de accesibilidad: tipo, identificador, etiqueta y valor de
    /// cada elemento, ordenados. Devuelve `nil` cuando la fuente no es ese árbol (WebView
    /// entrega HTML), y entonces se usa el texto normalizado completo.
    private static func semanticSignature(of source: String) -> String? {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { return nil }
        let entries = elements.map { element in
            ["type", "identifier", "label", "value"]
                .map { String(describing: element[$0] ?? "") }
                .joined(separator: "|")
        }
        // Ordenar hace la identidad independiente del orden de recorrido; el conteo de
        // repetidos distingue una lista de tres celdas iguales de una de cinco.
        return entries.sorted().joined(separator: "\n")
    }
}
