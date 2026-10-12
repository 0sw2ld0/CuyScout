import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Presentación de CuyScout para marketing y demos: diapositivas 16:9 con diagramas propios,
/// navegación con flechas, pantalla completa, exportación a PDF vectorial y copia de cada
/// diapositiva como imagen. Las cifras son las del benchmark publicado en el README.
struct PitchDeckView: View {
    @State private var index = 0
    @State private var message: String?

    private static let slides: [PitchSlide] = PitchSlide.allCases

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Presentación").font(.system(size: 22, weight: .bold))
                    Text("Cómo funciona CuyScout, lista para presentar o exportar").foregroundStyle(.secondary)
                }
                Spacer()
                if let message { Text(message).font(.callout).foregroundStyle(.secondary).transition(.opacity) }
                Button { copyCurrentSlide() } label: { Label("Copiar imagen", systemImage: "doc.on.doc") }
                    .help("Copia esta diapositiva como imagen para pegarla en otra presentación")
                Button { exportPDF() } label: { Label("Exportar PDF", systemImage: "arrow.down.doc") }
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Label("Pantalla completa", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .keyboardShortcut("f", modifiers: [.command, .control])
            }

            GeometryReader { proxy in
                let scale = min(proxy.size.width / PitchSlide.size.width, proxy.size.height / PitchSlide.size.height)
                Self.slides[index].view(animated: true)
                    .frame(width: PitchSlide.size.width, height: PitchSlide.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18 / max(scale, 0.01)))
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                    .id(index)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            }

            HStack(spacing: 14) {
                Button { go(-1) } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(index == 0)
                HStack(spacing: 7) {
                    ForEach(Self.slides.indices, id: \.self) { item in
                        Capsule()
                            .fill(item == index ? CuyScoutTheme.accent : CuyScoutTheme.border)
                            .frame(width: item == index ? 22 : 8, height: 8)
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.35)) { index = item } }
                            .help(Self.slides[item].title)
                    }
                }
                Button { go(1) } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(index == Self.slides.count - 1)
                Text("\(index + 1) / \(Self.slides.count) · \(Self.slides[index].title)")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("← → para avanzar · ⌃⌘F pantalla completa").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .background(CuyScoutTheme.canvas)
    }

    private func go(_ delta: Int) {
        let next = min(max(index + delta, 0), Self.slides.count - 1)
        guard next != index else { return }
        withAnimation(.easeInOut(duration: 0.35)) { index = next }
    }

    private func flash(_ text: String) {
        withAnimation { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { if message == text { message = nil } } }
    }

    @MainActor private func copyCurrentSlide() {
        let renderer = ImageRenderer(content: Self.slides[index].view(animated: false).frame(width: PitchSlide.size.width, height: PitchSlide.size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage else { flash("No se pudo copiar la diapositiva"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        flash("Diapositiva copiada")
    }

    @MainActor private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "CuyScout - Cómo funciona.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.writePDF(to: url)
            flash("PDF exportado")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            flash("No se pudo exportar: \(error.localizedDescription)")
        }
    }

    /// Una página por diapositiva. Cada una se dibuja como imagen a doble resolución: en modo
    /// vectorial los degradados y las transparencias de SwiftUI no salen como en pantalla.
    @MainActor static func writePDF(to url: URL) throws {
        var box = CGRect(origin: .zero, size: PitchSlide.size)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for slide in slides {
            let renderer = ImageRenderer(content: slide.view(animated: false).frame(width: PitchSlide.size.width, height: PitchSlide.size.height))
            renderer.scale = 2
            // En JPEG: sin comprimir, ocho diapositivas pesaban más de 30 MB.
            guard let raw = renderer.cgImage,
                  let jpeg = NSBitmapImageRep(cgImage: raw).representation(using: .jpeg, properties: [.compressionFactor: 0.9]),
                  let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileWriteUnknown) }
            context.beginPDFPage(nil)
            context.interpolationQuality = .high
            context.draw(image, in: box)
            context.endPDFPage()
        }
        context.closePDF()
    }
}

// MARK: - Diapositivas

enum PitchSlide: Int, CaseIterable {
    case cover, problem, howItWorks, generateReplay, robustness, measured, deliverables, closing

    static let size = CGSize(width: 1280, height: 720)

    var title: String {
        switch self {
        case .cover: "Portada"
        case .problem: "El problema"
        case .howItWorks: "Cómo funciona"
        case .generateReplay: "Generar una vez, repetir siempre"
        case .robustness: "Hecho para apps reales"
        case .measured: "Medido"
        case .deliverables: "Lo que recibe el equipo"
        case .closing: "Cierre"
        }
    }

    @ViewBuilder func view(animated: Bool) -> some View {
        switch self {
        case .cover: CoverSlide()
        case .problem: ProblemSlide()
        case .howItWorks: HowItWorksSlide(animated: animated)
        case .generateReplay: GenerateReplaySlide(animated: animated)
        case .robustness: RobustnessSlide()
        case .measured: MeasuredSlide()
        case .deliverables: DeliverablesSlide()
        case .closing: ClosingSlide()
        }
    }
}

private enum Deck {
    static let ink = Color(red: 0.07, green: 0.10, blue: 0.13)
    static let teal = Color(red: 0.16, green: 0.72, blue: 0.74)
    static let violet = Color(red: 0.55, green: 0.42, blue: 0.95)
    static let amber = Color(red: 0.98, green: 0.71, blue: 0.27)
    static let coral = Color(red: 0.96, green: 0.42, blue: 0.40)
    static let muted = Color.white.opacity(0.62)

    static var background: some View {
        ZStack {
            LinearGradient(colors: [ink, CuyScoutTheme.sidebar, CuyScoutTheme.accent.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [violet.opacity(0.28), .clear], center: UnitPoint(x: 0.92, y: 0.08), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [teal.opacity(0.22), .clear], center: UnitPoint(x: 0.05, y: 0.95), startRadius: 0, endRadius: 560)
        }
    }
}

/// Marco común: fondo, etiqueta de sección, título y pie con la marca.
private struct SlideFrame<Content: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Deck.background
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker.uppercased())
                    .font(.system(size: 15, weight: .bold)).tracking(3).foregroundStyle(Deck.teal)
                Text(title)
                    .font(.system(size: 46, weight: .heavy)).foregroundStyle(.white)
                    .padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                content.padding(.top, 34)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 72).padding(.top, 62).padding(.bottom, 70)
            HStack(spacing: 10) {
                CuyScoutMark(size: 26)
                Text("CuyScout").font(.system(size: 15, weight: .semibold)).foregroundStyle(Deck.muted)
                Spacer()
                Text("Pruebas iOS, más lejos").font(.system(size: 14)).foregroundStyle(Deck.muted.opacity(0.7))
            }
            .padding(.horizontal, 72).padding(.bottom, 28)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: PitchSlide.size.width, height: PitchSlide.size.height)
    }
}

private struct Pill: View {
    let text: String
    let icon: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
    }
}

private struct GlassCard<Content: View>: View {
    var tint: Color = Deck.teal
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(LinearGradient(colors: [tint.opacity(0.55), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
    }
}

private struct IconBadge: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 52
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.28))
            .shadow(color: tint.opacity(0.45), radius: 12, y: 4)
    }
}

// 1. Portada
private struct CoverSlide: View {
    var body: some View {
        ZStack {
            Deck.background
            HStack(spacing: 64) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("CUYSCOUT").font(.system(size: 17, weight: .bold)).tracking(4).foregroundStyle(Deck.teal)
                    Text("Agentes de IA que prueban tu app iOS…")
                        .font(.system(size: 58, weight: .heavy)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("…y dejan una prueba que se repite en segundos, sin volver a gastar en el agente.")
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(Deck.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Pill(text: "iPhone real y simulador", icon: "iphone")
                        Pill(text: "Sin código fuente", icon: "lock.shield")
                        Pill(text: "Copilot · Claude", icon: "sparkles")
                    }
                    .padding(.top, 8)
                }
                ZStack {
                    Circle().fill(RadialGradient(colors: [Deck.teal.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 230))
                        .frame(width: 460, height: 460)
                    Circle().strokeBorder(AngularGradient(colors: [Deck.teal, Deck.violet, Deck.teal], center: .center), lineWidth: 3)
                        .frame(width: 330, height: 330).opacity(0.7)
                    CuyScoutMark(size: 230)
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                }
            }
            .padding(.horizontal, 80)
        }
        .frame(width: PitchSlide.size.width, height: PitchSlide.size.height)
    }
}

// 2. El problema
private struct ProblemSlide: View {
    private let items: [(String, String, String, Color)] = [
        ("hand.tap", "Pruebas manuales lentas", "Cada versión se vuelve a probar a mano, pantalla por pantalla, en varios iPhone.", Deck.amber),
        ("wrench.and.screwdriver", "Scripts que se rompen", "Un cambio de diseño, un teclado que tapa un botón o una animación lenta y el script falla.", Deck.coral),
        ("text.page.badge.magnifyingglass", "Agentes que gastan de más", "Un agente con Appium lee el árbol XML entero en cada paso: decenas de miles de tokens por prueba.", Deck.violet),
    ]
    var body: some View {
        SlideFrame(kicker: "El problema", title: "Automatizar apps iOS sigue siendo caro y frágil") {
            HStack(spacing: 24) {
                ForEach(items, id: \.1) { item in
                    GlassCard(tint: item.3) {
                        VStack(alignment: .leading, spacing: 18) {
                            IconBadge(icon: item.0, tint: item.3, size: 62)
                            Text(item.1).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                            Text(item.2).font(.system(size: 20)).foregroundStyle(Deck.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(height: 340)
        }
    }
}

// 3. Cómo funciona: flujo animado
private struct HowItWorksSlide: View {
    let animated: Bool
    private let nodes: [(String, String, String, Color)] = [
        ("doc.text", "Escenario", "Gherkin en lenguaje natural", Deck.amber),
        ("sparkles", "Agente IA", "Copilot o Claude decide cada paso", Deck.violet),
        ("viewfinder", "CuyScout", "Muestra solo lo accionable y protege la sesión", Deck.teal),
        ("iphone", "iPhone o simulador", "El runner toca, escribe y verifica", Deck.coral),
        ("checkmark.seal", "Prueba grabada", "Lista para repetir y exportar", CuyScoutTheme.success),
    ]
    var body: some View {
        SlideFrame(kicker: "Cómo funciona", title: "Del escenario a una prueba ejecutable") {
            VStack(alignment: .leading, spacing: 40) {
                ZStack(alignment: .top) {
                    FlowConnector(count: nodes.count, animated: animated)
                        .frame(height: 140)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                            VStack(spacing: 14) {
                                IconBadge(icon: node.0, tint: node.3, size: 96)
                                Text(node.1).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                                Text(node.2).font(.system(size: 16)).foregroundStyle(Deck.muted)
                                    .multilineTextAlignment(.center).frame(width: 190).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                HStack(spacing: 18) {
                    Pill(text: "Observa: 1 llamada con controles y textos", icon: "eye")
                    Pill(text: "Actúa por selector, no por píxeles", icon: "scope")
                    Pill(text: "Aprende reglas para la próxima vez", icon: "brain.head.profile")
                }
            }
        }
    }
}

/// Línea punteada entre los nodos con puntos de luz que avanzan (estática al exportar).
private struct FlowConnector: View {
    let count: Int
    let animated: Bool
    var body: some View {
        GeometryReader { proxy in
            let step = proxy.size.width / CGFloat(count)
            let y: CGFloat = 48
            let start = step / 2 + 58, end = proxy.size.width - step / 2 - 58
            ZStack {
                Path { path in path.move(to: CGPoint(x: start, y: y)); path.addLine(to: CGPoint(x: end, y: y)) }
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 9]))
                if animated {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<3) { pulse in
                                let phase = (t / 3.2 + Double(pulse) / 3).truncatingRemainder(dividingBy: 1)
                                Circle().fill(Deck.teal).frame(width: 12, height: 12)
                                    .shadow(color: Deck.teal, radius: 8)
                                    .position(x: start + (end - start) * phase, y: y)
                            }
                        }
                    }
                } else {
                    ForEach(1..<count, id: \.self) { item in
                        Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundStyle(Deck.teal)
                            .position(x: step * CGFloat(item), y: y)
                    }
                }
            }
        }
    }
}

// 4. Generar una vez, repetir siempre
private struct GenerateReplaySlide: View {
    let animated: Bool
    var body: some View {
        SlideFrame(kicker: "Generar una vez, repetir siempre", title: "El agente trabaja una vez; la prueba se queda") {
            HStack(alignment: .top, spacing: 26) {
                GlassCard(tint: Deck.violet) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { IconBadge(icon: "sparkles", tint: Deck.violet); Text("1 · Generar").font(.system(size: 28, weight: .bold)).foregroundStyle(.white) }
                        bullet("El agente lee el escenario y explora la app")
                        bullet("Resuelve precondiciones y pantallas nuevas")
                        bullet("Guarda lo aprendido para la próxima corrida")
                        bullet("Graba cada paso con su selector")
                    }
                }
                Image(systemName: "arrow.right").font(.system(size: 40, weight: .heavy)).foregroundStyle(Deck.teal)
                    .frame(maxHeight: .infinity)
                    .opacity(animated ? 1 : 0.9)
                GlassCard(tint: Deck.teal) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { IconBadge(icon: "play.fill", tint: Deck.teal); Text("2 · Repetir").font(.system(size: 28, weight: .bold)).foregroundStyle(.white) }
                        bullet("Sin agente: 0 tokens por corrida")
                        bullet("En segundos, en simulador o iPhone real")
                        bullet("Espera a cada pantalla y cierra el teclado")
                        bullet("Video y diagnóstico si algo falla")
                    }
                }
                Image(systemName: "arrow.right").font(.system(size: 40, weight: .heavy)).foregroundStyle(Deck.teal)
                    .frame(maxHeight: .infinity)
                GlassCard(tint: CuyScoutTheme.success) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { IconBadge(icon: "shippingbox.fill", tint: CuyScoutTheme.success); Text("3 · Llevar").font(.system(size: 28, weight: .bold)).foregroundStyle(.white) }
                        bullet("Appium: TypeScript, Python, Java")
                        bullet("Flujos YAML de Maestro")
                        bullet("JUnit para el CI")
                        bullet("Sin quedar atado a CuyScout")
                    }
                }
            }
            .frame(height: 360)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Deck.teal).frame(width: 7, height: 7).offset(y: -3)
            Text(text).font(.system(size: 19)).foregroundStyle(Color.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// 5. Robustez
private struct RobustnessSlide: View {
    private let items: [(String, String, String)] = [
        ("hourglass", "Espera a la pantalla", "Toca cuando la app quedó quieta, no mientras carga."),
        ("keyboard.chevron.compact.down", "Cierra el teclado", "Después de escribir, sin enviar el formulario."),
        ("scope", "Toques con sentido", "Convierte un toque en coordenadas en un toque por selector."),
        ("arrow.clockwise", "Reintento seguro", "Repite un toque solo si la pantalla no cambió nada."),
        ("rectangle.slash", "Detecta bloqueos", "Pantalla en negro, runner ocupado o iPhone bloqueado."),
        ("video.fill", "Video del fallo", "Captura, pantalla, pasos y video para entender qué pasó."),
    ]
    var body: some View {
        SlideFrame(kicker: "Hecho para apps reales", title: "Resuelve lo que hace frágil una prueba") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 3), spacing: 22) {
                ForEach(items, id: \.1) { item in
                    HStack(alignment: .top, spacing: 18) {
                        IconBadge(icon: item.0, tint: Deck.teal, size: 54)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.1).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            Text(item.2).font(.system(size: 17)).foregroundStyle(Deck.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(22)
                    .frame(height: 150, alignment: .topLeading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.12)))
                }
            }
        }
    }
}

// 6. Medido: tokens por escenario completo (benchmark del README)
private struct MeasuredSlide: View {
    // Cifras y proporciones tal como las publica el README.
    private let rows: [(String, Double, Double, String)] = [
        ("Opus 5", 3_946, 65_476, "16,6x"),
        ("Sonnet 5", 3_689, 72_199, "19,6x"),
        ("Haiku 4.5", 12_551, 128_648, "10,2x"),
    ]
    var body: some View {
        SlideFrame(kicker: "Medido", title: "Hasta 19,6 veces menos tokens que Appium") {
            HStack(alignment: .top, spacing: 46) {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 22) {
                        legend("CuyScout", Deck.teal)
                        legend("Appium 3.2.2", Color.white.opacity(0.35))
                    }
                    ForEach(rows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.0).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                                Spacer()
                                Text("\(row.3) menos")
                                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Deck.teal)
                            }
                            bar(value: row.1, label: Self.thousands(row.1), color: Deck.teal)
                            bar(value: row.2, label: Self.thousands(row.2), color: Color.white.opacity(0.35))
                        }
                    }
                }
                .frame(width: 700)
                VStack(alignment: .leading, spacing: 20) {
                    stat("284", "tokens cuesta leer una pantalla con CuyScout", "frente a 2 043 del árbol completo")
                    stat("17,3x", "menos tokens hasta tener la prueba automatizada lista", "5 354 frente a 92 478")
                    Text("Mismo escenario de pago, mismos simuladores, sin acceso al código. Tokens contados en el tráfico HTTP. Medición propia, repetible.")
                        .font(.system(size: 14)).foregroundStyle(Deck.muted.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static func thousands(_ value: Double) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.groupingSeparator = " "; formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") + " tokens"
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 16, height: 16); Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(Deck.muted) }
    }

    private func bar(value: Double, label: String, color: Color) -> some View {
        let maximum = rows.map(\.2).max() ?? 1
        return GeometryReader { proxy in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(width: max(8, (proxy.size.width - 150) * value / maximum))
                Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(Deck.muted).fixedSize()
            }
        }
        .frame(height: 18)
    }

    private func stat(_ number: String, _ text: String, _ detail: String) -> some View {
        GlassCard(tint: Deck.teal) {
            VStack(alignment: .leading, spacing: 6) {
                Text(number).font(.system(size: 54, weight: .heavy)).foregroundStyle(Deck.teal)
                Text(text).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.system(size: 15)).foregroundStyle(Deck.muted)
            }
        }
        .frame(height: 190)
    }
}

// 7. Lo que recibe el equipo
private struct DeliverablesSlide: View {
    private let items: [(String, String, String, Color)] = [
        ("tag.fill", "Informe de identificadores", "Qué controles no tienen identificador, con captura, prioridad y el nombre sugerido. Para el equipo de desarrollo, en HTML, Markdown y CSV.", Deck.amber),
        ("timer", "Tiempo y costo por corrida", "Cuánto tardó la prueba y cuántos tokens estimados consumió el agente.", Deck.violet),
        ("waveform.path.ecg", "Pruebas estables o inestables", "Cada repetición se registra: distingue una prueba que falla a veces de un fallo real de la app.", Deck.teal),
        ("doc.text.magnifyingglass", "Diagnóstico entendible", "Qué paso falló, qué había en pantalla y qué hacer, en lenguaje claro.", Deck.coral),
    ]
    var body: some View {
        SlideFrame(kicker: "Lo que recibe el equipo", title: "Más que una prueba: información para cada equipo") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 22), GridItem(.flexible(), spacing: 22)], spacing: 22) {
                ForEach(items, id: \.1) { item in
                    HStack(alignment: .top, spacing: 20) {
                        IconBadge(icon: item.0, tint: item.3, size: 60)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.1).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                            Text(item.2).font(.system(size: 17)).foregroundStyle(Deck.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(height: 170, alignment: .topLeading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(item.3.opacity(0.35)))
                }
            }
        }
    }
}

// 8. Cierre
private struct ClosingSlide: View {
    var body: some View {
        ZStack {
            Deck.background
            VStack(spacing: 34) {
                CuyScoutMark(size: 120).shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                Text("CuyScout").font(.system(size: 64, weight: .heavy)).foregroundStyle(.white)
                Text("Pruebas iOS con agentes de IA: más rápidas, más baratas y repetibles.")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(Deck.muted)
                HStack(spacing: 22) {
                    number("10–20x", "menos tokens que Appium")
                    number("0", "tokens al repetir una prueba")
                    number("3", "formatos para llevarla: Appium, Maestro, JUnit")
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 90)
        }
        .frame(width: PitchSlide.size.width, height: PitchSlide.size.height)
    }

    private func number(_ value: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.system(size: 50, weight: .heavy)).foregroundStyle(Deck.teal)
            Text(text).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 300, height: 170)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.14)))
    }
}
