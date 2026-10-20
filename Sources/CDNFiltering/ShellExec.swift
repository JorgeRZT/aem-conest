import Foundation

/// Lanza un ejecutable en su propio grupo de procesos (vía perl/setpgrp) para poder cancelar
/// el pipeline entero (grep | awk | sort…) de una vez.
final class ShellExec: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0

    private func setPid(_ p: pid_t) { lock.lock(); pid = p; lock.unlock() }

    func cancel() {
        lock.lock(); let p = pid; lock.unlock()
        if p > 0 { kill(-p, SIGTERM) }
    }

    /// Devuelve el código de salida (-1 si no se pudo lanzar). Si `onError` es nil, stderr se
    /// mezcla con stdout.
    func run(_ executable: String, _ args: [String], cwd: URL? = nil,
             onOutput: @escaping @Sendable (Data) -> Void,
             onError: (@Sendable (Data) -> Void)? = nil) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", "setpgrp(0,0); exec @ARGV or die \"exec: $!\"", executable] + args
        if let cwd { process.currentDirectoryURL = cwd }

        let out = Pipe()
        let err: Pipe? = onError == nil ? nil : Pipe()
        process.standardOutput = out
        process.standardError = err ?? out

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            group.leave()
            onOutput(Data("Could not run: \(error.localizedDescription)".utf8))
            return -1
        }
        // Sin esto el extremo de escritura sigue abierto en este proceso y nunca llega el EOF.
        try? out.fileHandleForWriting.close()
        try? err?.fileHandleForWriting.close()

        func drain(_ pipe: Pipe, _ sink: @escaping @Sendable (Data) -> Void) {
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                } else {
                    sink(data)
                }
            }
        }
        drain(out, onOutput)
        if let err, let onError { drain(err, onError) }

        setPid(process.processIdentifier)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { c.resume() }
        }
        setPid(0)
        return process.terminationStatus
    }
}

/// Acumula bytes de forma segura entre hilos.
final class DataCollector: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
