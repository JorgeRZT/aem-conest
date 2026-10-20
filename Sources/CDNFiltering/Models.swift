import Foundation

/// A flow step: a script from the scripts folder + its arguments.
struct FlowStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var script: String
    var args: String
    var enabled = true

    /// Variables used by the argument template, e.g. "start" for `{cleaned} {start} {end}`.
    var variables: Set<String> {
        let regex = try! NSRegularExpression(pattern: #"\{([A-Za-z_]+)\}"#)
        let ns = args as NSString
        return Set(regex.matches(in: args, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        })
    }

    var needsDateRange: Bool { !variables.isDisjoint(with: ["start", "end"]) }

    static let defaultFlow: [FlowStep] = [
        FlowStep(script: "clean.sh", args: "{input} {cleaned}"),
        FlowStep(script: "byDay.sh", args: "{cleaned}"),
        FlowStep(script: "hitsByDomain.sh", args: "{cleaned}"),
        FlowStep(script: "byDayAndDomain.sh", args: "{cleaned}"),
        FlowStep(script: "hitsByDomainAndDate.sh", args: "{cleaned} {start} {end}"),
    ]
}

/// Variables available in a step's arguments.
enum FlowVariable {
    static let docs: [(name: String, text: String)] = [
        ("{input}", "Original dropped file"),
        ("{cleaned}", "Cleaned file: the original without its extension + _clean.csv"),
        ("{dir}", "Folder of the original file"),
        ("{name}", "Original file name without extension"),
        ("{start}", "Start date (YYYY-MM-DD)"),
        ("{end}", "End date (YYYY-MM-DD)"),
    ]

    static func values(for input: URL, range: (start: String, end: String)?) -> [String: String] {
        let cleaned = input.deletingPathExtension().path + "_clean.csv"
        var v = [
            "input": input.path,
            "cleaned": cleaned,
            "dir": input.deletingLastPathComponent().path,
            "name": input.deletingPathExtension().lastPathComponent,
        ]
        if let range {
            v["start"] = range.start
            v["end"] = range.end
        }
        return v
    }

    /// Splits the template on spaces and substitutes each `{variable}`. Every token is an
    /// independent argument, so paths with spaces need no quoting.
    static func resolve(_ template: String, values: [String: String]) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"\{([A-Za-z_]+)\}"#)
        return try template.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { token in
            var result = String(token)
            let ns = result as NSString
            for m in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                let key = ns.substring(with: m.range(at: 1))
                guard let value = values[key] else { throw FlowError.unknownVariable(key) }
                result = (result as NSString).replacingCharacters(in: m.range, with: value)
            }
            return result
        }
    }
}

enum FlowError: LocalizedError {
    case unknownVariable(String)
    case missingScript(String)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .unknownVariable(let v): return "Unknown variable: {\(v)}"
        case .missingScript(let s): return "Script not found: \(s)"
        case .missingFile(let p): return "File not found: \(p) (is a previous step that creates it missing?)"
        }
    }
}

enum RunStatus {
    case pending, running, done, skipped, failed, cancelled
}

struct StepRun: Identifiable {
    let id = UUID()
    var script: String
    var command = ""
    var output = ""
    var status = RunStatus.pending
    var startedAt: Date?
    var duration: TimeInterval?
    var exitCode: Int32?
}

struct FileRun: Identifiable {
    let id = UUID()
    var url: URL
    var steps: [StepRun]
    var status = RunStatus.pending
}
