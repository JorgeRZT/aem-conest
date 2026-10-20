import SwiftUI

struct ScriptsView: View {
    @EnvironmentObject var scripts: ScriptStore
    @EnvironmentObject var flow: FlowStore

    @State private var selected: String?
    @State private var text = ""
    @State private var loaded = ""
    @State private var showNew = false
    @State private var newName = ""
    @State private var confirmDelete = false

    private var dirty: Bool { selected != nil && text != loaded }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(scripts.names, id: \.self, selection: $selected) { name in
                    HStack {
                        Image(systemName: scripts.isDefault(name) ? "doc.text" : "doc.badge.plus")
                        Text(name)
                    }
                    .tag(name)
                }
                Divider()
                HStack {
                    Button { newName = ""; showNew = true } label: { Image(systemName: "plus") }.help("Nuevo script")
                    Button { confirmDelete = true } label: { Image(systemName: "minus") }
                        .disabled(selected == nil).help("Eliminar script")
                    Spacer()
                    Button { scripts.revealInFinder() } label: { Image(systemName: "folder") }.help("Mostrar carpeta en Finder")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)

            VStack(alignment: .leading, spacing: 8) {
                if let name = selected {
                    HStack {
                        Text(name).font(.headline)
                        if dirty { Text("● sin guardar").font(.caption).foregroundStyle(.orange) }
                        Spacer()
                        if scripts.isDefault(name) {
                            Button("Restaurar original") {
                                scripts.resetToDefault(name)
                                load(name)
                            }
                        }
                        Button("Guardar") { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!dirty)
                    }
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .border(Color.secondary.opacity(0.3))
                    HStack {
                        Text("Se ejecuta con bash. Para usarlo, añádelo como paso en «Flujo».")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Añadir al flujo") {
                            flow.steps.append(FlowStep(script: name, args: "{cleaned}"))
                        }
                    }
                } else {
                    Text("Selecciona un script o crea uno nuevo con +")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)
            .frame(minWidth: 400)
        }
        .navigationTitle("Scripts")
        .onAppear { if selected == nil { selected = scripts.names.first } }
        .onChange(of: selected) { old, new in
            if let old, dirty, scripts.exists(old) { scripts.save(text, as: old) }
            if let new { load(new) } else { text = ""; loaded = "" }
        }
        .sheet(isPresented: $showNew) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nuevo script").font(.headline)
                TextField("nombre (se añade .sh)", text: $newName).textFieldStyle(.roundedBorder)
                    .onSubmit(createScript)
                HStack {
                    Spacer()
                    Button("Cancelar") { showNew = false }
                    Button("Crear", action: createScript).keyboardShortcut(.defaultAction)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20).frame(width: 340)
        }
        .confirmationDialog("¿Eliminar \(selected ?? "")?", isPresented: $confirmDelete) {
            Button("Eliminar", role: .destructive) {
                if let s = selected { selected = nil; scripts.delete(s) }
            }
        } message: {
            Text("Los scripts originales se pueden recuperar reiniciando la carpeta de scripts.")
        }
    }

    @State private var loadedName: String?

    private func load(_ name: String) {
        text = scripts.content(name)
        loaded = text
        loadedName = name
    }

    private func save() {
        guard let name = selected else { return }
        scripts.save(text, as: name)
        loaded = text
    }

    private func createScript() {
        if let name = scripts.create(named: newName) {
            showNew = false
            selected = name
        }
    }
}
