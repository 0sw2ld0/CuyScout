import AppKit
import CuyScoutCore
import SwiftUI

/// Editor de `fixtures/credentials.test.json`: los alias y campos que usan los escenarios y los fragmentos.
/// Los valores se muestran ocultos; el archivo se guarda con permisos de solo el dueño.
struct CredentialsView: View {
    @Environment(\.dismiss) private var dismiss
    let project: ScoutProject

    private struct Field: Identifiable { let id = UUID(); var name: String; var value: String }
    private struct Alias: Identifiable { let id = UUID(); var name: String; var fields: [Field] }

    @State private var aliases: [Alias] = []
    @State private var revealed: Set<UUID> = []
    @State private var unsupported = false
    @State private var ignored = true
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Credenciales de prueba").font(.title2.bold())
            Text("Cada alias es un usuario de prueba y cada campo uno de sus datos (por ejemplo password_android). Los escenarios y los fragmentos piden el alias; el agente no ve los valores.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if unsupported {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Este archivo tiene datos que la app no maneja").fontWeight(.medium)
                        Text("Para no perderlos, edítalo a mano: fixtures/credentials.test.json.").font(.callout).foregroundStyle(.secondary)
                        Button("Abrir el archivo") { NSWorkspace.shared.open(CredentialsStore.url(in: project.url)) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            } else {
                if !ignored {
                    GroupBox {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Este archivo no está en el .gitignore del proyecto").fontWeight(.medium)
                                Text("Si el repositorio se comparte, no guardes aquí claves reales: usa usuarios de prueba.").font(.callout).foregroundStyle(.secondary)
                                Button("Añadir al .gitignore") { addToGitIgnore() }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($aliases) { $alias in aliasBox($alias) }
                        Button("Añadir alias", systemImage: "plus") { aliases.append(Alias(name: "", fields: [Field(name: "password_android", value: "")])) }
                    }
                }.frame(minHeight: 220)
            }

            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if saved { Text("Guardado.").font(.callout).foregroundStyle(.green) }
            HStack {
                Spacer()
                Button("Cerrar") { dismiss() }
                if !unsupported { Button("Guardar") { save() }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 440)
        .onAppear(perform: load)
    }

    private func aliasBox(_ alias: Binding<Alias>) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Alias (p. ej. demo_user)", text: alias.name).textFieldStyle(.roundedBorder).font(.body.weight(.semibold))
                    Button(role: .destructive) { aliases.removeAll { $0.id == alias.wrappedValue.id } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Quitar este alias")
                }
                ForEach(alias.fields) { $field in
                    HStack {
                        TextField("campo", text: $field.name).textFieldStyle(.roundedBorder).frame(maxWidth: 190)
                        Group {
                            if revealed.contains(field.id) { TextField("valor", text: $field.value) } else { SecureField("valor", text: $field.value) }
                        }.textFieldStyle(.roundedBorder)
                        Button { toggle(field.id) } label: { Image(systemName: revealed.contains(field.id) ? "eye.slash" : "eye") }
                            .buttonStyle(.borderless).help(revealed.contains(field.id) ? "Ocultar el valor" : "Mostrar el valor")
                        Button { alias.wrappedValue.fields.removeAll { $0.id == field.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Quitar este campo")
                    }
                }
                Button("Añadir campo", systemImage: "plus") { alias.wrappedValue.fields.append(Field(name: "", value: "")) }.buttonStyle(.borderless)
            }.padding(8)
        }
    }

    private func toggle(_ id: UUID) { if revealed.contains(id) { revealed.remove(id) } else { revealed.insert(id) } }

    private func load() {
        do {
            let document = try CredentialsStore.load(in: project.url)
            unsupported = document.hasUnsupportedValues
            aliases = document.aliases.sorted { $0.key < $1.key }.map { alias in
                Alias(name: alias.key, fields: alias.value.sorted { $0.key < $1.key }.map { Field(name: $0.key, value: $0.value) })
            }
        } catch { unsupported = true; self.error = "No se pudo leer el archivo: \(error.localizedDescription)" }
        ignored = CredentialsStore.isGitIgnored(in: project.url)
    }

    private func save() {
        saved = false
        var result: [String: [String: String]] = [:]
        for alias in aliases {
            let name = alias.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { error = "Hay un alias sin nombre."; return }
            guard result[name] == nil else { error = "El alias «\(name)» está repetido."; return }
            var fields: [String: String] = [:]
            for field in alias.fields {
                let key = field.name.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { error = "Hay un campo sin nombre en «\(name)»."; return }
                guard fields[key] == nil else { error = "El campo «\(key)» está repetido en «\(name)»."; return }
                fields[key] = field.value
            }
            result[name] = fields
        }
        do { try CredentialsStore.save(result, in: project.url); error = nil; saved = true; ignored = CredentialsStore.isGitIgnored(in: project.url) }
        catch { self.error = error.localizedDescription }
    }

    private func addToGitIgnore() {
        do { try CredentialsStore.addToGitIgnore(in: project.url); ignored = true; error = nil } catch { self.error = error.localizedDescription }
    }
}
