import AppKit
import CuyScoutCore
import SwiftUI

/// Indicador de un replay en curso: el cuy en el centro de un anillo que gira, la etapa,
/// el paso en vivo («Paso 7 de 29 · tocar «Continuar»»), la barra de avance y el tiempo.
struct ReplayProgressCard: View {
    let progress: ReplayProgress?
    let startedAt: Date?
    @State private var spinning = false
    @State private var breathing = false

    private var fraction: Double {
        guard let progress, progress.total > 0 else { return 0 }
        return Double(progress.current) / Double(progress.total)
    }
    private var preparing: Bool { progress?.stage != "ejecutando" }

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.12), lineWidth: 7)
                // Avance real cuando ya hay pasos; mientras prepara, un arco que gira.
                Circle()
                    .trim(from: 0, to: preparing ? 0.28 : max(0.04, fraction))
                    .stroke(AngularGradient(colors: [.accentColor.opacity(0.2), .accentColor, .purple], center: .center),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(preparing ? (spinning ? 360 : 0) : -90))
                    .animation(preparing ? .linear(duration: 1.1).repeatForever(autoreverses: false) : .spring(duration: 0.5), value: spinning)
                    .animation(.spring(duration: 0.5), value: fraction)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 54, height: 54)
                    .scaleEffect(breathing ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: breathing)
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 7) {
                Text(preparing ? "Preparando la prueba" : "Ejecutando la prueba")
                    .font(.title3.bold())
                if let progress, !preparing {
                    Text("Paso \(progress.current) de \(progress.total)")
                        .font(.headline).foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: progress.current)
                    Text(progress.step)
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .id(progress.step)
                    ProgressView(value: fraction)
                        .tint(.accentColor)
                        .animation(.spring(duration: 0.5), value: fraction)
                } else {
                    Text("Abriendo el dispositivo, instalando la app y conectando el runner…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        let seconds = Int(context.date.timeIntervalSince(startedAt))
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.purple.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.18)))
        .animation(.easeInOut(duration: 0.35), value: progress)
        .onAppear { spinning = true; breathing = true }
    }
}
