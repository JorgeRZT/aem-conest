import Foundation
import AppKit

enum AppPaths {
    /// ~/Library/Application Support/AEM Conest/ (migra la carpeta antigua "CDN Filtering" si existe).
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let new = base.appendingPathComponent("AEM Conest", isDirectory: true)
        let old = base.appendingPathComponent("CDN Filtering", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        return new
    }()
}

/// Carpeta de scripts editable por el usuario, en ~/Library/Application Support/AEM Conest/scripts.
@MainActor
final class ScriptStore: ObservableObject {
    @Published private(set) var names: [String] = []

    let directory = AppPaths.support.appendingPathComponent("scripts", isDirectory: true)

    init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for d in DefaultScripts.all where !FileManager.default.fileExists(atPath: url(d.name).path) {
            try? write(d.content + "\n", to: d.name)
        }
        reload()
    }

    func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }

    func isDefault(_ name: String) -> Bool { DefaultScripts.all.contains { $0.name == name } }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        names = files.filter { $0.hasSuffix(".sh") }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func content(_ name: String) -> String {
        (try? String(contentsOf: url(name), encoding: .utf8)) ?? ""
    }

    func write(_ text: String, to name: String) throws {
        try text.write(to: url(name), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url(name).path)
    }

    func save(_ text: String, as name: String) {
        try? write(text, to: name)
        reload()
    }

    /// Crea un script nuevo con una plantilla. Devuelve el nombre final o nil si ya existe / es inválido.
    func create(named raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return nil }
        if !name.hasSuffix(".sh") { name += ".sh" }
        guard !exists(name) else { return nil }
        let template = """
        #!/usr/bin/env bash
        # uso: \(name) entrada.csv
        set -u

        in="${1:?uso: $0 entrada.csv}"

        # Escribe aquí tu lógica. Lo que imprimas aparecerá en los resultados.
        wc -l < "$in"

        """
        save(template, as: name)
        return name
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
        reload()
    }

    func resetToDefault(_ name: String) {
        guard let d = DefaultScripts.all.first(where: { $0.name == name }) else { return }
        save(d.content + "\n", as: name)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }
}

/// Flujo de ejecución (lista ordenada de pasos), guardado en flow.json.
@MainActor
final class FlowStore: ObservableObject {
    @Published var steps: [FlowStep] {
        didSet { save() }
    }

    private let file = AppPaths.support.appendingPathComponent("flow.json")

    init() {
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([FlowStep].self, from: data) {
            steps = decoded
        } else {
            steps = FlowStep.defaultFlow
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        try? enc.encode(steps).write(to: file, options: .atomic)
    }

    func resetToDefault() { steps = FlowStep.defaultFlow }
}
