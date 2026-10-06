import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Informe del backlog de identificadores de un proyecto: una página HTML de alto nivel (con
/// el recorte de cada elemento en su pantalla), y las versiones Markdown y CSV para llevarlo a
/// Jira u otra herramienta. Se escribe en `<proyecto>/reports/`.
public enum IdentifierReport {
    public struct Row: Sendable, Equatable {
        public let finding: IdentifierFinding
        public let suggestedIdentifier: String
        public let scenarios: [String]
        /// Recorte PNG del elemento con el resto de la pantalla difuminado.
        public let crop: Data?
        public let fromRecordingOnly: Bool
    }

    public struct Output: Sendable {
        public let html: URL
        public let markdown: URL
        public let csv: URL
        public let pending: Int
        public let highPriority: Int
    }

    // MARK: - Datos

    public static func rows(projectDirectory: URL) -> [Row] {
        let store = IdentifierBacklogStore(projectDirectory: projectDirectory)
        let backlog = store.snapshot
        let scenariosBySession = scenarioNames(projectDirectory: projectDirectory)
        var findings = Array(backlog.findings.values)
        // Grabaciones anteriores al backlog: lo que las pruebas ya usan por texto o coordenadas.
        for (sessionID, scenario, step) in fragileRecordedSteps(projectDirectory: projectDirectory) {
            let (label, how, type) = step
            if let index = findings.firstIndex(where: { !label.isEmpty && $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
                findings[index].usedBy[sessionID] = how
                continue
            }
            let key = "rec|" + IdentifierBacklogStore.slug("\(scenario) \(label)")
            guard !findings.contains(where: { $0.key == key }) else { continue }
            findings.append(IdentifierFinding(key: key, kind: how == "coordenadas" && label.hasPrefix("toque") ? .noTextNoIdentifier : .missingIdentifier,
                                              screenKey: "grabaciones", screen: "Visto en grabaciones (sin captura)", type: type, label: label,
                                              identifier: nil, frame: [0, 0, 0, 0], usedBy: [sessionID: how], timesSeen: 1,
                                              firstSeen: Date(), lastSeen: Date(), status: .pending, resolvedIdentifier: nil))
        }
        let images = loadScreens(backlog: backlog, directory: store.directory)
        return findings.map { finding in
            let screen = backlog.screens[finding.screenKey]
            let crop = images[finding.screenKey].flatMap { image in
                screen.flatMap { cropElement(in: image, frame: finding.frame, widthPoints: $0.widthPoints) }
            }
            return Row(finding: finding, suggestedIdentifier: suggestedIdentifier(for: finding, known: backlog.knownIdentifiers),
                       scenarios: finding.usedBy.keys.map { scenariosBySession[$0] ?? "sesión \($0.prefix(8))" }.sorted(),
                       crop: crop, fromRecordingOnly: finding.screenKey == "grabaciones")
        }.sorted(by: order)
    }

    static func order(_ lhs: Row, _ rhs: Row) -> Bool {
        let left = lhs.finding, right = rhs.finding
        if left.status != right.status { return left.status == .pending }
        if left.isHighPriority != right.isHighPriority { return left.isHighPriority }
        if left.screen != right.screen { return left.screen < right.screen }
        return (left.frame[1], left.frame[0]) < (right.frame[1], right.frame[0])
    }

    /// Sesión → escenario, desde `output/<escenario>.cuyscout.json`.
    static func scenarioNames(projectDirectory: URL) -> [String: String] {
        var names: [String: String] = [:]
        for (url, json) in artifacts(projectDirectory: projectDirectory) {
            if let id = (json["session"] as? [String: Any])?["id"] as? String { names[id] = url.lastPathComponent.replacingOccurrences(of: ".cuyscout.json", with: "") }
        }
        return names
    }

    static func fragileRecordedSteps(projectDirectory: URL) -> [(String, String, (String, String, String))] {
        var result: [(String, String, (String, String, String))] = []
        for (url, json) in artifacts(projectDirectory: projectDirectory) {
            guard let sessionID = (json["session"] as? [String: Any])?["id"] as? String,
                  let steps = (json["recording"] as? [String: Any])?["steps"] as? [[String: Any]] else { continue }
            let scenario = url.lastPathComponent.replacingOccurrences(of: ".cuyscout.json", with: "")
            for step in steps where step["success"] as? Bool != false {
                guard let action = step["action"] as? [String: Any], let type = action["type"] as? String else { continue }
                if type == "tap", let x = action["x"] as? Double, let y = action["y"] as? Double {
                    result.append((sessionID, scenario, ("toque en (\(Int(x)), \(Int(y)))", "coordenadas", "desconocido")))
                } else if ["tapElement", "typeElement", "clearElement"].contains(type),
                          let selector = action["selector"] as? [String: Any], let strategy = selector["strategy"] as? String,
                          strategy == "label" || strategy == "value", let value = selector["value"] as? String {
                    result.append((sessionID, scenario, (IdentifierBacklogStore.redact(value), "texto", type == "tapElement" ? "button" : "textField")))
                }
            }
        }
        return result
    }

    private static func artifacts(projectDirectory: URL) -> [(URL, [String: Any])] {
        let output = projectDirectory.appendingPathComponent("output", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix(".cuyscout.json") }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.map { (url, $0) }
        }
    }

    // MARK: - Identificador sugerido

    /// Con la convención que ya usa la app (`btn_login` → `btn_…`; `loginButton` → camelCase).
    public static func suggestedIdentifier(for finding: IdentifierFinding, known: [String]) -> String {
        if finding.kind == .duplicateIdentifier, let identifier = finding.identifier { return "\(identifier)_1, \(identifier)_2… (uno distinto por elemento)" }
        let type = finding.type.lowercased()
        let defaultPrefix = type.contains("button") ? "btn" : type.contains("field") || type.contains("textview") || type.contains("search") ? "input"
            : type.contains("cell") ? "cell" : type.contains("switch") || type.contains("toggle") ? "switch" : type.contains("link") ? "link"
            : type.contains("tab") ? "tab" : type.contains("picker") ? "picker" : "item"
        let prefixes = known.compactMap { $0.split(separator: "_").first.map(String.init) }.filter { $0.count <= 6 }
        let prefix = prefixes.first { $0.hasPrefix(defaultPrefix.prefix(3)) } ?? defaultPrefix
        let stopwords: Set<String> = ["de", "la", "el", "con", "tu", "su", "y", "a", "en", "para", "los", "las", "del", "al", "un", "una", "por", "cuadro", "texto", "nombre"]
        var words = IdentifierBacklogStore.slug(finding.label.replacingOccurrences(of: "•••", with: " "))
            .split(separator: "-").map(String.init).filter { !stopwords.contains($0) && !$0.allSatisfy(\.isNumber) }
        if words.isEmpty {
            let x = finding.frame[0] + finding.frame[2] / 2, y = finding.frame[1]
            words = (finding.screenKey == "grabaciones" ? [] : Array(finding.screenKey.split(separator: "-").prefix(2).map(String.init)))
                + [y < 200 ? "arriba" : "abajo", x > 260 ? "derecha" : x < 120 ? "izquierda" : "centro"]
        }
        words = Array(words.prefix(4))
        let camel = known.count >= 3 && known.filter { !$0.contains("_") && $0.contains(where: \.isUppercase) }.count * 2 > known.count
        if camel {
            let suffix = type.contains("button") ? "Button" : type.contains("field") || type.contains("search") ? "Field" : type.contains("textview") ? "TextView"
                : type.contains("cell") ? "Cell" : type.contains("switch") || type.contains("toggle") ? "Switch" : type.contains("link") ? "Link" : "Item"
            return ([words.first ?? ""] + words.dropFirst().map(\.capitalized)).joined() + suffix
        }
        return ([prefix] + words).joined(separator: "_")
    }

    // MARK: - Recortes

    private static func loadScreens(backlog: IdentifierBacklog, directory: URL) -> [String: CGImage] {
        var images: [String: CGImage] = [:]
        for (key, screen) in backlog.screens {
            guard let path = screen.screenshot, let data = try? Data(contentsOf: directory.appendingPathComponent(path)),
                  let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            images[key] = image
        }
        return images
    }

    /// El elemento nítido con un borde, su entorno difuminado (sin datos legibles de otros
    /// controles) y a lo más 520 px de ancho.
    static func cropElement(in image: CGImage, frame: [Double], widthPoints: Double) -> Data? {
        guard frame.count == 4, frame[2] > 0, frame[3] > 0, widthPoints > 0 else { return nil }
        let scale = Double(image.width) / widthPoints
        let element = CGRect(x: frame[0] * scale, y: frame[1] * scale, width: frame[2] * scale, height: frame[3] * scale)
        let padding = 60 * scale
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = element.insetBy(dx: -padding, dy: -padding).intersection(bounds).integral
        guard !area.isEmpty, let cropped = image.cropping(to: area) else { return nil }
        let width = Int(area.width), height = Int(area.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let blurred = CIImage(cgImage: cropped).clampedToExtent().applyingGaussianBlur(sigma: 8 * scale / 3).cropped(to: CIImage(cgImage: cropped).extent)
        if let blurredImage = ciContext.createCGImage(blurred, from: CIImage(cgImage: cropped).extent) { context.draw(blurredImage, in: full) }
        else { context.draw(cropped, in: full) }
        // CoreGraphics dibuja desde abajo: se invierte la Y del elemento dentro del recorte.
        let local = CGRect(x: element.minX - area.minX, y: Double(height) - (element.maxY - area.minY), width: element.width, height: element.height)
        context.saveGState()
        context.clip(to: local)
        context.draw(cropped, in: full)
        context.restoreGState()
        context.setStrokeColor(CGColor(red: 0.91, green: 0.2, blue: 0.24, alpha: 1))
        context.setLineWidth(max(3, 2 * scale / 1.5))
        context.stroke(local.insetBy(dx: -3 * scale / 2, dy: -3 * scale / 2))
        guard let result = context.makeImage() else { return nil }
        return encodePNG(result, maxWidth: 520)
    }

    private static func encodePNG(_ image: CGImage, maxWidth: Int) -> Data? {
        var output = image
        if image.width > maxWidth {
            let height = Int(Double(image.height) * Double(maxWidth) / Double(image.width))
            if let context = CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
                if let scaled = context.makeImage() { output = scaled }
            }
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, output, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: - Escritura

    @discardableResult
    public static func write(projectDirectory: URL, projectName: String, now: Date = Date()) throws -> Output {
        let rows = rows(projectDirectory: projectDirectory)
        let folder = projectDirectory.appendingPathComponent("reports", isDirectory: true)
        let crops = folder.appendingPathComponent("identificadores-capturas", isDirectory: true)
        try FileManager.default.createDirectory(at: crops, withIntermediateDirectories: true)
        var cropFiles: [String: String] = [:]
        for row in rows {
            guard let crop = row.crop else { continue }
            let name = "\(row.finding.key).png"
            try crop.write(to: crops.appendingPathComponent(name))
            cropFiles[row.finding.key] = "identificadores-capturas/\(name)"
        }
        let html = folder.appendingPathComponent("identificadores.html")
        let markdown = folder.appendingPathComponent("identificadores.md")
        let csv = folder.appendingPathComponent("identificadores.csv")
        try htmlReport(rows: rows, projectName: projectName, now: now).write(to: html, atomically: true, encoding: .utf8)
        try markdownReport(rows: rows, projectName: projectName, now: now, cropFiles: cropFiles).write(to: markdown, atomically: true, encoding: .utf8)
        try csvReport(rows: rows, cropFiles: cropFiles).write(to: csv, atomically: true, encoding: .utf8)
        let pending = rows.filter { $0.finding.status == .pending }
        ScoutLog.app.info("identificadores", "Informe generado", ["proyecto": projectDirectory.path, "pendientes": pending.count])
        return Output(html: html, markdown: markdown, csv: csv, pending: pending.count, highPriority: pending.filter { $0.finding.isHighPriority }.count)
    }

    static func usage(_ row: Row) -> String {
        guard !row.finding.usedBy.isEmpty else { return "Solo visto" }
        let hows = Set(row.finding.usedBy.values).sorted()
        return "Usado por " + hows.joined(separator: " y ")
    }

    // MARK: Markdown

    public static func markdownReport(rows: [Row], projectName: String, now: Date, cropFiles: [String: String] = [:]) -> String {
        let pending = rows.filter { $0.finding.status == .pending }
        let resolved = rows.filter { $0.finding.status == .resolved }
        var lines = ["# Elementos sin identificador · \(projectName)", "",
                     "Generado por CuyScout el \(dateText(now)). Cada fila es un elemento que las pruebas automáticas no pueden ubicar de forma estable: hace falta un `accessibilityIdentifier` (o uno único).", "",
                     "| Pendientes | Prioridad alta | Prioridad media | Resueltos |", "| ---: | ---: | ---: | ---: |",
                     "| \(pending.count) | \(pending.filter { $0.finding.isHighPriority }.count) | \(pending.filter { !$0.finding.isHighPriority }.count) | \(resolved.count) |", ""]
        lines.append("**Por problema:** " + IdentifierFinding.Kind.allCases.map { kind in "\(kind.title): \(pending.filter { $0.finding.kind == kind }.count)" }.joined(separator: " · "))
        lines.append("")
        for (title, subset) in [("Prioridad alta — las pruebas ya dependen de estos elementos", pending.filter { $0.finding.isHighPriority }),
                                ("Prioridad media — vistos sin identificador", pending.filter { !$0.finding.isHighPriority })] where !subset.isEmpty {
            lines += ["## \(title)", "", "| Pantalla | Elemento | Texto visible | Problema | Uso | Identificador sugerido | Escenarios | Captura |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
            for row in subset {
                let finding = row.finding
                let crop = cropFiles[finding.key].map { "![](\($0))" } ?? "—"
                lines.append("| \(md(finding.screen)) | \(md(finding.type)) | \(md(finding.label.isEmpty ? "(sin texto)" : finding.label)) | \(finding.kind.title) | \(usage(row)) | `\(md(row.suggestedIdentifier))` | \(md(row.scenarios.joined(separator: ", ").isEmpty ? "—" : row.scenarios.joined(separator: ", "))) | \(crop) |")
            }
            lines.append("")
        }
        if !resolved.isEmpty {
            lines += ["## Resueltos", "", "| Pantalla | Elemento | Texto visible | Identificador nuevo |", "| --- | --- | --- | --- |"]
            for row in resolved { lines.append("| \(md(row.finding.screen)) | \(md(row.finding.type)) | \(md(row.finding.label)) | `\(md(row.finding.resolvedIdentifier ?? ""))` |") }
            lines.append("")
        }
        lines.append("Los textos se muestran sin datos personales (números, correos y nombres van ocultos).")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func md(_ text: String) -> String { text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }

    // MARK: CSV

    public static func csvReport(rows: [Row], cropFiles: [String: String] = [:]) -> String {
        let header = ["estado", "prioridad", "problema", "pantalla", "tipo", "texto_visible", "identificador_actual", "identificador_sugerido", "uso", "escenarios", "veces_visto", "primera_vez", "ultima_vez", "captura", "clave"]
        var lines = [header.joined(separator: ",")]
        for row in rows {
            let finding = row.finding
            let values = [finding.status.rawValue, finding.isHighPriority ? "alta" : "media", finding.kind.title, finding.screen, finding.type, finding.label,
                          finding.identifier ?? finding.resolvedIdentifier ?? "", row.suggestedIdentifier, usage(row), row.scenarios.joined(separator: "; "),
                          String(finding.timesSeen), dateText(finding.firstSeen), dateText(finding.lastSeen), cropFiles[finding.key] ?? "", finding.key]
            lines.append(values.map(csv).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csv(_ value: String) -> String {
        // Las celdas que empiezan con = + - @ se neutralizan: Excel las ejecutaría como fórmula.
        let safe = ["=", "+", "-", "@"].contains(where: value.hasPrefix) ? "'" + value : value
        return safe.contains(where: { ",\"\n".contains($0) }) ? "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : safe
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "es"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: HTML

    public static func htmlReport(rows: [Row], projectName: String, now: Date) -> String {
        let pending = rows.filter { $0.finding.status == .pending }
        let resolved = rows.filter { $0.finding.status == .resolved }
        let high = pending.filter { $0.finding.isHighPriority }
        let screens = Dictionary(grouping: pending, by: { $0.finding.screen }).map { ($0.key, $0.value) }.sorted { $0.1.count > $1.1.count }
        let maxPerScreen = max(1, screens.first?.1.count ?? 1)
        func esc(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func card(_ row: Row) -> String {
            let finding = row.finding
            let image = row.crop.map { "<img src=\"data:image/png;base64,\($0.base64EncodedString())\" alt=\"\">" } ?? "<div class=\"noimg\">Sin captura</div>"
            let scenarios = row.scenarios.isEmpty ? "" : "<div class=\"meta\">Escenarios: \(esc(row.scenarios.joined(separator: ", ")))</div>"
            return """
            <article class="item">
              <div class="shot">\(image)</div>
              <div class="body">
                <div class="tags"><span class="tag \(finding.isHighPriority ? "high" : "mid")">\(finding.isHighPriority ? "Prioridad alta" : "Prioridad media")</span><span class="tag kind">\(finding.kind.title)</span><span class="tag use">\(esc(usage(row)))</span></div>
                <h3>\(esc(finding.label.isEmpty ? "(sin texto)" : finding.label))</h3>
                <div class="meta">\(esc(finding.type)) · visto \(finding.timesSeen) \(finding.timesSeen == 1 ? "vez" : "veces")\(finding.identifier.map { " · id actual <code>\(esc($0))</code>" } ?? "")</div>
                <div class="suggest">Identificador sugerido <code>\(esc(row.suggestedIdentifier))</code></div>
                \(scenarios)
              </div>
            </article>
            """
        }
        let bars = screens.prefix(8).map { screen, items in
            "<div class=\"bar\"><span class=\"name\">\(esc(screen))</span><span class=\"track\"><span style=\"width:\(Int(Double(items.count) / Double(maxPerScreen) * 100))%\"></span></span><span class=\"num\">\(items.count)</span></div>"
        }.joined(separator: "\n")
        let kinds = IdentifierFinding.Kind.allCases.map { kind in
            "<div class=\"kindstat\"><b>\(pending.filter { $0.finding.kind == kind }.count)</b><span>\(kind.title)</span></div>"
        }.joined()
        let sections = screens.map { screen, items in
            "<section><h2>\(esc(screen)) <small>\(items.count)</small></h2><div class=\"grid\">\(items.map(card).joined(separator: "\n"))</div></section>"
        }.joined(separator: "\n")
        let resolvedList = resolved.isEmpty ? "" : "<section><h2>Resueltos <small>\(resolved.count)</small></h2><ul class=\"resolved\">" + resolved.map {
            "<li>\(esc($0.finding.screen)) · \(esc($0.finding.label.isEmpty ? $0.finding.type : $0.finding.label)) → <code>\(esc($0.finding.resolvedIdentifier ?? ""))</code></li>"
        }.joined() + "</ul></section>"
        return """
        <!doctype html>
        <html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Identificadores pendientes · \(esc(projectName))</title>
        <style>
        :root { --bg:#f6f7fb; --card:#fff; --text:#1d1f2b; --muted:#6b7084; --line:#e4e6ef; --accent:#3b5bfd; --high:#e5383b; --mid:#f2a541; --ok:#2a9d8f; }
        @media (prefers-color-scheme: dark) { :root { --bg:#111319; --card:#1b1e27; --text:#eef0f6; --muted:#9aa0b4; --line:#2b2f3c; } }
        * { box-sizing:border-box } body { margin:0; font:15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:var(--bg); color:var(--text); }
        main { max-width:1100px; margin:0 auto; padding:32px 16px 64px; }
        header h1 { margin:0 0 4px; font-size:28px } header p { margin:0; color:var(--muted) }
        .stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:12px; margin:24px 0; }
        .stat { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:16px; } .stat b { display:block; font-size:32px; } .stat span { color:var(--muted) }
        .stat.high b { color:var(--high) } .stat.mid b { color:var(--mid) } .stat.ok b { color:var(--ok) }
        .panel { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:18px; margin-bottom:16px; }
        .panel h2 { margin:0 0 12px; font-size:17px }
        .bar { display:grid; grid-template-columns:minmax(120px,240px) 1fr 40px; gap:10px; align-items:center; margin:6px 0; font-size:14px }
        .bar .name { overflow:hidden; text-overflow:ellipsis; white-space:nowrap } .track { height:10px; background:var(--line); border-radius:6px; overflow:hidden }
        .track span { display:block; height:100%; background:linear-gradient(90deg,var(--accent),#8b5cf6); } .num { text-align:right; color:var(--muted) }
        .kinds { display:flex; flex-wrap:wrap; gap:10px } .kindstat { background:var(--bg); border-radius:10px; padding:10px 14px } .kindstat b { font-size:20px; margin-right:6px }
        section h2 { font-size:20px; margin:32px 0 12px } section h2 small { color:var(--muted); font-weight:500 }
        .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)); gap:14px }
        .item { background:var(--card); border:1px solid var(--line); border-radius:14px; overflow:hidden; display:flex; flex-direction:column }
        .shot { background:#0b0d12; display:flex; justify-content:center; } .shot img { max-width:100%; max-height:220px; display:block }
        .noimg { color:#8a8fa3; padding:40px 0; font-size:13px } .body { padding:12px 14px 14px }
        .body h3 { margin:6px 0 2px; font-size:16px; word-break:break-word } .meta { color:var(--muted); font-size:13px; margin-top:2px }
        .suggest { margin-top:8px; font-size:14px } code { background:var(--bg); border:1px solid var(--line); border-radius:6px; padding:1px 6px; font-size:13px }
        .tags { display:flex; flex-wrap:wrap; gap:6px } .tag { font-size:12px; padding:2px 8px; border-radius:999px; background:var(--bg); border:1px solid var(--line) }
        .tag.high { background:var(--high); color:#fff; border-color:transparent } .tag.mid { background:var(--mid); color:#1d1f2b; border-color:transparent }
        .resolved li { margin:4px 0 } footer { color:var(--muted); font-size:13px; margin-top:40px }
        </style></head><body><main>
        <header><h1>Identificadores pendientes · \(esc(projectName))</h1>
        <p>Elementos que las pruebas automáticas no pueden ubicar de forma estable. Agregar un <code>accessibilityIdentifier</code> único los vuelve automatizables y, en los que no tienen texto, también accesibles con VoiceOver. Generado por CuyScout el \(esc(dateText(now))).</p></header>
        <div class="stats">
          <div class="stat"><b>\(pending.count)</b><span>Pendientes</span></div>
          <div class="stat high"><b>\(high.count)</b><span>Prioridad alta: las pruebas ya dependen de ellos</span></div>
          <div class="stat mid"><b>\(pending.count - high.count)</b><span>Prioridad media: vistos sin identificador</span></div>
          <div class="stat ok"><b>\(resolved.count)</b><span>Resueltos</span></div>
        </div>
        <div class="panel"><h2>Por problema</h2><div class="kinds">\(kinds)</div></div>
        <div class="panel"><h2>Pantallas con más pendientes</h2>\(bars.isEmpty ? "<p>Sin pendientes.</p>" : bars)</div>
        \(sections)
        \(resolvedList)
        <footer>Los textos y capturas no muestran datos personales: los números, correos y nombres van ocultos y el entorno de cada elemento aparece difuminado.</footer>
        </main></body></html>
        """
    }
}
