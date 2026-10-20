import Foundation

/// Ejecuta el flujo sobre cada fichero, en cola y paso a paso.
@MainActor
final class Runner: ObservableObject {
    @Published var files: [FileRun] = []
    @Published var isRunning = false

    private let shell = ShellExec()
    private var cancelRequested = false
    private var task: Task<Void, Never>?

    nonisolated private static let maxOutput = 4_000_000

    func start(inputs: [URL], flow: [FlowStep], scripts: ScriptStore, range: (start: String, end: String)?) {
        guard !isRunning else { return }
        let steps = flow.filter(\.enabled)
        files = inputs.map { FileRun(url: $0, steps: steps.map { StepRun(script: $0.script) }) }
        isRunning = true
        cancelRequested = false
        task = Task { [weak self] in
            guard let self else { return }
            for f in self.files.indices {
                if self.cancelRequested { self.markCancelled(from: f); break }
                await self.run(fileIndex: f, steps: steps, scripts: scripts, range: range)
            }
            self.isRunning = false
        }
    }

    func cancel() {
        cancelRequested = true
        shell.cancel()
    }

    private func markCancelled(from f: Int) {
        for i in f..<files.count {
            files[i].status = .cancelled
            for s in files[i].steps.indices where files[i].steps[s].status == .pending {
                files[i].steps[s].status = .cancelled
            }
        }
    }

    private func run(fileIndex f: Int, steps: [FlowStep], scripts: ScriptStore, range: (start: String, end: String)?) async {
        files[f].status = .running
        let values = FlowVariable.values(for: files[f].url, range: range)
        var failed = false

        for (s, step) in steps.enumerated() {
            if cancelRequested { break }
            if failed {
                files[f].steps[s].status = .skipped
                files[f].steps[s].output = "Omitido: un paso anterior falló."
                continue
            }
            if step.needsDateRange && range == nil {
                files[f].steps[s].status = .skipped
                files[f].steps[s].output = "Omitido: este paso usa {start}/{end} y no hay rango de fechas activado."
                continue
            }

            let scriptURL = scripts.url(step.script)
            let args: [String]
            do {
                guard scripts.exists(step.script) else { throw FlowError.missingScript(step.script) }
                args = try FlowVariable.resolve(step.args, values: values)
                // Un paso con {input} lee el original (y puede crear {cleaned}); uno que solo usa
                // {cleaned} necesita que un paso previo ya lo haya generado.
                let tokens = step.args.split(whereSeparator: { $0 == " " || $0 == "\t" })
                let required = tokens.contains("{input}") ? "input" : (tokens.contains("{cleaned}") ? "cleaned" : nil)
                if let key = required, let p = values[key], !FileManager.default.fileExists(atPath: p) {
                    throw FlowError.missingFile(p)
                }
            } catch {
                files[f].steps[s].status = .failed
                files[f].steps[s].output = error.localizedDescription
                failed = true
                continue
            }

            files[f].steps[s].command = (["bash", step.script] + args).map(Self.display).joined(separator: " ")
            files[f].steps[s].status = .running
            files[f].steps[s].startedAt = Date()
            let started = Date()

            let code = await exec(script: scriptURL, args: args, cwd: scripts.directory) { [weak self] text in
                Task { @MainActor in self?.files[f].steps[s].output = text }
            }

            files[f].steps[s].duration = Date().timeIntervalSince(started)
            files[f].steps[s].exitCode = code
            if cancelRequested {
                files[f].steps[s].status = .cancelled
            } else if code == 0 {
                files[f].steps[s].status = .done
            } else {
                files[f].steps[s].status = .failed
                failed = true
            }
        }

        if cancelRequested {
            files[f].status = .cancelled
            for s in files[f].steps.indices where files[f].steps[s].status == .pending {
                files[f].steps[s].status = .cancelled
            }
        } else {
            files[f].status = failed ? .failed : .done
        }
    }

    private static func display(_ arg: String) -> String {
        arg.contains(where: { " \"'".contains($0) }) ? "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'" : arg
    }

    private func exec(script: URL, args: [String], cwd: URL, onOutput: @escaping @Sendable (String) -> Void) async -> Int32 {
        let buffer = OutputBuffer()
        return await shell.run("/bin/bash", [script.path] + args, cwd: cwd) { data in
            onOutput(buffer.append(data, limit: Self.maxOutput))
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data, limit: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        if data.count < limit { data.append(chunk) }
        var text = String(decoding: data, as: UTF8.self)
        if data.count >= limit { text += "\n… salida truncada …" }
        return text
    }
}
