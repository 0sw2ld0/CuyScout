import CuyScoutCore
import SwiftUI

private struct CleanupTarget: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let deviceIDs: [String]
    let artifactID: String?
}

struct StorageView: View {
    @ObservedObject var model: ScoutAppModel
    @State private var pending: CleanupTarget?
    @State private var working = false
    @State private var result: String?

    private var benchmarkCandidates: [SimulatorStorageItem] {
        model.simulatorStorage.filter {
            $0.state.caseInsensitiveCompare("Shutdown") == .orderedSame &&
            ($0.name.localizedCaseInsensitiveContains("Bench") || $0.name.localizedCaseInsensitiveContains("Benchmark"))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Almacenamiento y limpieza").font(.largeTitle.bold())
                Text("Datos del gateway conectado. La limpieza nunca es automática: revisa cada selección antes de confirmar.")
                    .foregroundStyle(.secondary)
                if let result { Text(result).foregroundStyle(.secondary) }

                HStack(spacing: 20) {
                    GroupBox("Simuladores") {
                        VStack(alignment: .leading) {
                            Text(ByteCountFormatter.string(fromByteCount: model.simulatorStorage.reduce(0) { $0 + $1.dataBytes }, countStyle: .file))
                                .font(.title2.bold())
                            Text("\(model.simulatorStorage.count) dispositivos · tamaño de datos informado por CoreSimulator")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    GroupBox("Artefactos del gateway") {
                        VStack(alignment: .leading) {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(model.artifactStatus?.totalBytes ?? 0), countStyle: .file))
                                .font(.title2.bold())
                            Text("\(model.artifactStatus?.persistedCount ?? model.catalog.count) archivos · retención: \(model.artifactStatus?.artifactRetention == 0 ? "ilimitada" : String(model.artifactStatus?.artifactRetention ?? 0))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Simuladores de benchmark apagados").font(.headline)
                            Spacer()
                            Button("Limpiar los \(benchmarkCandidates.count) seleccionados…") {
                                let items = benchmarkCandidates
                                pending = CleanupTarget(
                                    title: "Eliminar \(items.count) simuladores de benchmark",
                                    detail: "Se eliminarán permanentemente los simuladores apagados cuyos nombres contienen «Bench» o «Benchmark». Datos estimados: \(ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.dataBytes }, countStyle: .file)). Sus pruebas y apps instaladas dentro de ellos se perderán; los artefactos exportados no se borran.",
                                    deviceIDs: items.map(\.id), artifactID: nil)
                            }
                            .disabled(working || benchmarkCandidates.isEmpty)
                        }
                        Text("Solo se sugieren por nombre. Verifica que no necesites sus datos; los simuladores encendidos y en uso no se pueden borrar.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.simulatorStorage) { device in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text("\(device.state) · \(device.id)")
                                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: device.dataBytes, countStyle: .file))
                                    .foregroundStyle(.secondary)
                                Button("Eliminar…") {
                                    pending = CleanupTarget(title: "Eliminar \(device.name)",
                                        detail: "Se eliminará permanentemente este simulador y sus datos (aprox. \(ByteCountFormatter.string(fromByteCount: device.dataBytes, countStyle: .file))).",
                                        deviceIDs: [device.id], artifactID: nil)
                                }
                                .disabled(working || device.state.caseInsensitiveCompare("Shutdown") != .orderedSame)
                            }
                            Divider()
                        }
                    }.padding(8)
                }

                GroupBox("Artefactos persistidos") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Borrar aquí elimina la copia del gateway, no los archivos exportados en tus proyectos. Una sesión activa debe cerrarse primero.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.catalog, id: \.sessionID) { artifact in
                            HStack {
                                Text(artifact.sessionID).textSelection(.enabled)
                                Spacer()
                                Text(artifact.deviceName).foregroundStyle(.secondary)
                                Button("Eliminar…") {
                                    pending = CleanupTarget(title: "Eliminar artefacto", detail: "Se eliminará permanentemente del gateway el artefacto \(artifact.sessionID). Comprueba que tienes una copia exportada si deseas conservar esta prueba.", deviceIDs: [], artifactID: artifact.sessionID)
                                }.disabled(working)
                            }
                            Divider()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }.padding(24)
        }
        .alert(item: $pending) { target in
            Alert(title: Text(target.title), message: Text(target.detail),
                primaryButton: .destructive(Text("Eliminar")) { Task { await delete(target) } },
                secondaryButton: .cancel())
        }
    }

    private func delete(_ target: CleanupTarget) async {
        working = true
        defer { working = false }
        var failures: [String] = []
        for id in target.deviceIDs {
            do { try await model.deleteSimulator(id) }
            catch { failures.append("\(id): \(error.localizedDescription)") }
        }
        if let id = target.artifactID {
            do { try await model.deleteArtifact(id) }
            catch { failures.append("\(id): \(error.localizedDescription)") }
        }
        await model.refresh()
        result = failures.isEmpty ? "Limpieza completada." : "Algunos elementos no se pudieron eliminar: \(failures.joined(separator: "; "))"
    }
}
