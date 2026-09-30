import Foundation

extension LearnedLesson {
    func withID(_ id: String) -> LearnedLesson {
        LearnedLesson(id: id, scope: scope, projectKey: projectKey, sessionID: sessionID, title: title, observation: observation,
                      recommendation: recommendation, evidence: evidence, tags: tags, confidence: confidence, createdAt: createdAt,
                      updatedAt: updatedAt, occurrences: occurrences, failures: failures ?? 0)
    }
}

/// Formato de una regla aprendida en `<proyecto>/rules/<id>.md`: frontmatter corto y tres
/// secciones legibles. Lo escribe CuyScout (ya sin datos sensibles) y lo puede editar una persona.
public enum ProjectRuleFile {
    public static let idPrefix = "rule:"
    public static let directoryName = "rules"

    /// `rule:<slug>` a partir del título: minúsculas, sin tildes, guiones y 60 caracteres como máximo.
    public static func id(forTitle title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        var slug = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII { slug.unicodeScalars.append(scalar) }
            else if !slug.hasSuffix("-") { slug.append("-") }
        }
        slug = String(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return idPrefix + (slug.isEmpty ? "regla" : slug)
    }

    public static func fileName(for id: String) -> String {
        let slug = id.hasPrefix(idPrefix) ? String(id.dropFirst(idPrefix.count)) : id
        let safe = slug.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return (safe.isEmpty ? "regla" : safe) + ".md"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let sections = (observation: "**Observación:**", action: "**Qué hacer:**", evidence: "**Evidencia:**")

    public static func render(_ lesson: LearnedLesson) -> String {
        var lines = [
            "---",
            "titulo: \(oneLine(lesson.title))",
            "etiquetas: [\(lesson.tags.map(oneLine).joined(separator: ", "))]",
            "confianza: \(String(format: "%.2f", lesson.confidence))",
            "usos: \(lesson.occurrences)",
            "fallos: \(lesson.failures ?? 0)",
            "creada: \(dayFormatter.string(from: lesson.createdAt))",
            "actualizada: \(dayFormatter.string(from: lesson.updatedAt))",
            "---",
            "",
            "\(sections.observation) \(lesson.observation)",
            "",
            "\(sections.action) \(lesson.recommendation)"
        ]
        if let evidence = lesson.evidence, !evidence.isEmpty { lines += ["", "\(sections.evidence) \(evidence)"] }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Lee una regla con tolerancia: sin frontmatter o sin secciones, el cuerpo entero es "Qué hacer".
    public static func parse(_ text: String, id: String) -> LearnedLesson? {
        var fields: [String: String] = [:]
        var body = text
        let lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                fields[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            body = lines[(end + 1)...].joined(separator: "\n")
        }
        let observation = section(sections.observation, in: body)
        let action = section(sections.action, in: body)
        let evidence = section(sections.evidence, in: body)
        let recommendation = action ?? (observation == nil ? body.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        let title = fields["titulo"] ?? fields["title"] ?? String(id.dropFirst(idPrefix.count)).replacingOccurrences(of: "-", with: " ")
        guard let recommendation, !recommendation.isEmpty, !title.isEmpty else { return nil }
        let tags = (fields["etiquetas"] ?? fields["tags"] ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let created = fields["creada"].flatMap(dayFormatter.date(from:)) ?? Date()
        return LearnedLesson(id: id, scope: .project, title: title, observation: observation ?? title, recommendation: recommendation,
                             evidence: evidence, tags: tags, confidence: fields["confianza"].flatMap(Double.init) ?? 0.8,
                             createdAt: created, updatedAt: fields["actualizada"].flatMap(dayFormatter.date(from:)) ?? created,
                             occurrences: fields["usos"].flatMap(Int.init) ?? 1, failures: fields["fallos"].flatMap(Int.init) ?? 0)
    }

    private static func section(_ marker: String, in body: String) -> String? {
        guard let start = body.range(of: marker) else { return nil }
        var rest = body[start.upperBound...]
        let others = [sections.observation, sections.action, sections.evidence].filter { $0 != marker }
        if let next = others.compactMap({ rest.range(of: $0)?.lowerBound }).min() { rest = rest[..<next] }
        let value = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func oneLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
    }

    public static let readme = """
    # Reglas aprendidas

    Cada archivo es algo que un agente aprendió al ejecutar las pruebas de este proyecto:
    cómo alcanzar una precondición, cómo es una pantalla o qué evitar. Los agentes las leen
    antes de ejecutar un escenario, así la siguiente corrida no redescubre lo mismo.

    - Las escribe CuyScout (`POST /lessons` con `scope: "project"` en una sesión abierta con
      `cuyscout:projectDir`); pasan por el filtro de datos sensibles antes de guardarse.
    - Revísalas en el diff como cualquier cambio: corrige, borra o edita el texto a mano.
    - `usos` y `fallos` cuentan cuántas veces ayudó o falló; bajo `confianza: 0.30` la regla
      deja de entregarse a los agentes.
    - **Nunca** incluyas credenciales, números de cuenta ni datos personales: esos van solo
      en `fixtures/credentials.test.json`.

    Formato:

    ```markdown
    ---
    titulo: Ingreso con usuario recordado
    etiquetas: [login, precondicion]
    confianza: 0.80
    usos: 1
    fallos: 0
    creada: 2026-01-01
    actualizada: 2026-01-01
    ---

    **Observación:** qué se vio en la app.

    **Qué hacer:** cómo resolverlo la próxima vez.
    ```

    """
}
