import Foundation

struct HitRow: Identifiable, Hashable {
    var id: String { day + "|" + domain }
    let day: String
    let domain: String
    let hits: Int
}

struct DayTotal: Identifiable {
    var id: String { day }
    let day: String
    let date: Date
    let hits: Int
}

struct StackRow: Identifiable {
    var id: String { day + "|" + domain }
    let day: String
    let date: Date
    let domain: String
    let hits: Int
}

struct DomainTotal: Identifiable {
    var id: String { domain }
    let domain: String
    let hits: Int
    let share: Double
}

/// Filtered and aggregated data consumed by the charts and tables.
struct Derived {
    var rows: [HitRow] = []
    var byDay: [DayTotal] = []
    var byDomain: [DomainTotal] = []
    var stack: [StackRow] = []
    var heat: [HitRow] = []
    var total = 0
    var peakDay: DayTotal?

    static let stackTop = 6
    static let heatTop = 15
}

enum Fmt {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.groupingSeparator = "."
        f.usesGroupingSeparator = true
        return f
    }()

    static func n(_ v: Int) -> String { number.string(from: NSNumber(value: v)) ?? "\(v)" }
}

@MainActor
final class DashboardModel: ObservableObject {
    // Sources and options
    @Published var sources: [URL] = []
    @Published var cleanFirst = true
    @Published var reuseClean = true

    // State
    @Published var isLoading = false
    @Published var phase = ""
    @Published var phaseStart: Date?
    @Published var errorMessage: String?
    @Published var notes: [String] = []

    // Data
    @Published private(set) var allRows: [HitRow] = []
    @Published private(set) var allDomains: [DomainTotal] = []
    @Published private(set) var minDate = Date()
    @Published private(set) var maxDate = Date()

    // Filters
    @Published var start = Date() { didSet { recompute() } }
    @Published var end = Date() { didSet { recompute() } }
    @Published var selectedDomains: Set<String> = [] { didSet { recompute() } }

    @Published private(set) var derived = Derived()

    private let shell = ShellExec()
    private var cancelled = false
    private var suspendRecompute = false

    private static let awkProgram = #"""
    {
      d = substr($0, 2, 10)
      if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { bad++; next }
      n = split($0, f, ",")
      h = f[n]; gsub(/["\r]/, "", h)
      c[d "\t" h]++
    }
    END {
      for (k in c) print k "\t" c[k]
      print "#invalid\t\t" bad + 0
    }
    """#

    // MARK: Sources

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !sources.contains(url) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                sources.append(url)
            }
        }
        if !sources.isEmpty {
            cleanFirst = !sources.allSatisfy { $0.lastPathComponent.contains("_clean") }
        }
    }

    func cleanedURL(for src: URL) -> URL {
        URL(fileURLWithPath: src.deletingPathExtension().path + "_clean.csv")
    }

    // MARK: Analysis

    func cancel() {
        cancelled = true
        shell.cancel()
    }

    func analyze(scripts: ScriptStore) {
        guard !isLoading, !sources.isEmpty else { return }
        isLoading = true
        cancelled = false
        errorMessage = nil
        notes = []
        let sources = self.sources

        Task { [weak self] in
            guard let self else { return }
            var acc: [String: Int] = [:]
            var invalid = 0
            var failure: String?

            for (i, src) in sources.enumerated() {
                if self.cancelled { break }
                let tag = sources.count > 1 ? " (\(i + 1)/\(sources.count))" : ""
                var target = src

                if self.cleanFirst {
                    let cleaned = self.cleanedURL(for: src)
                    target = cleaned
                    if self.reuseClean && Self.isFresh(cleaned, comparedTo: src) {
                        self.notes.append("\(cleaned.lastPathComponent): reused (newer than the original)")
                    } else {
                        self.setPhase("Cleaning \(src.lastPathComponent)\(tag)")
                        guard scripts.exists("clean.sh") else { failure = "Script clean.sh not found"; break }
                        let out = DataCollector()
                        let code = await self.shell.run("/bin/bash", [scripts.url("clean.sh").path, src.path, cleaned.path],
                                                        cwd: scripts.directory, onOutput: { out.append($0) })
                        if self.cancelled { break }
                        if code != 0 { failure = "clean.sh failed on \(src.lastPathComponent): \(out.text)"; break }
                        self.notes.append(out.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                self.setPhase("Counting \(target.lastPathComponent)\(tag)")
                let out = DataCollector(), err = DataCollector()
                let code = await self.shell.run("/usr/bin/awk", [Self.awkProgram, target.path],
                                                onOutput: { out.append($0) }, onError: { err.append($0) })
                if self.cancelled { break }
                if code != 0 { failure = "awk failed on \(target.lastPathComponent): \(err.text)"; break }

                for line in out.text.split(separator: "\n") {
                    let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                    guard f.count == 3, let n = Int(f[2]) else { continue }
                    if f[0] == "#invalid" { invalid += n } else { acc[String(f[0]) + "\t" + String(f[1]), default: 0] += n }
                }
            }

            self.isLoading = false
            self.phaseStart = nil
            if self.cancelled { self.notes.append("Analysis cancelled."); return }
            if let failure { self.errorMessage = failure; return }
            if invalid > 0 { self.notes.append("\(Fmt.n(invalid)) lines without a valid date (characters 2–11) ignored.") }

            let rows = acc.map { key, hits -> HitRow in
                let p = key.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                return HitRow(day: String(p[0]), domain: p.count > 1 ? String(p[1]) : "", hits: hits)
            }
            self.load(rows)
        }
    }

    private func setPhase(_ text: String) {
        phase = text
        phaseStart = Date()
    }

    private static func isFresh(_ cleaned: URL, comparedTo src: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let c = try? cleaned.resourceValues(forKeys: keys).contentModificationDate,
              let s = try? src.resourceValues(forKeys: keys).contentModificationDate else { return false }
        return c >= s
    }

    // MARK: Filters and aggregates

    private func load(_ rows: [HitRow]) {
        suspendRecompute = true
        allRows = rows
        var totals: [String: Int] = [:]
        for r in rows { totals[r.domain, default: 0] += r.hits }
        let sum = max(totals.values.reduce(0, +), 1)
        allDomains = totals.map { DomainTotal(domain: $0.key, hits: $0.value, share: Double($0.value) / Double(sum)) }
            .sorted { $0.hits > $1.hits }
        let days = rows.map(\.day).sorted()
        minDate = days.first.flatMap { Fmt.day.date(from: $0) } ?? Date()
        maxDate = days.last.flatMap { Fmt.day.date(from: $0) } ?? Date()
        start = minDate
        end = maxDate
        selectedDomains = Set(totals.keys)
        suspendRecompute = false
        recompute()
    }

    func resetFilters() {
        suspendRecompute = true
        start = minDate
        end = maxDate
        selectedDomains = Set(allDomains.map(\.domain))
        suspendRecompute = false
        recompute()
    }

    /// Date shortcut relative to the last day with data.
    func setLastDays(_ n: Int?) {
        suspendRecompute = true
        end = maxDate
        if let n, let d = Calendar.current.date(byAdding: .day, value: -(n - 1), to: maxDate) {
            start = max(d, minDate)
        } else {
            start = minDate
        }
        suspendRecompute = false
        recompute()
    }

    private func recompute() {
        guard !suspendRecompute else { return }
        let s = Fmt.day.string(from: start), e = Fmt.day.string(from: end)
        let rows = allRows.filter { $0.day >= s && $0.day <= e && selectedDomains.contains($0.domain) }

        var dayTotals: [String: Int] = [:], domTotals: [String: Int] = [:]
        for r in rows {
            dayTotals[r.day, default: 0] += r.hits
            domTotals[r.domain, default: 0] += r.hits
        }
        let total = dayTotals.values.reduce(0, +)

        let byDay = dayTotals.compactMap { k, v -> DayTotal? in
            Fmt.day.date(from: k).map { DayTotal(day: k, date: $0, hits: v) }
        }.sorted { $0.day < $1.day }

        let ranked = domTotals.sorted { $0.value > $1.value }
        let byDomain = ranked.map { DomainTotal(domain: $0.key, hits: $0.value, share: total > 0 ? Double($0.value) / Double(total) : 0) }

        // Stacking: the top N domains + "Others".
        let top = Set(ranked.prefix(Derived.stackTop).map(\.key))
        var stackAcc: [String: Int] = [:]
        for r in rows { stackAcc[r.day + "\t" + (top.contains(r.domain) ? r.domain : "Others"), default: 0] += r.hits }
        let stack = stackAcc.compactMap { k, v -> StackRow? in
            let p = k.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let d = Fmt.day.date(from: String(p[0])) else { return nil }
            return StackRow(day: String(p[0]), date: d, domain: String(p[1]), hits: v)
        }

        let heatDomains = Set(ranked.prefix(Derived.heatTop).map(\.key))

        derived = Derived(
            rows: rows.sorted { ($0.day, $1.hits) < ($1.day, $0.hits) },
            byDay: byDay,
            byDomain: byDomain,
            stack: stack,
            heat: rows.filter { heatDomains.contains($0.domain) },
            total: total,
            peakDay: byDay.max { $0.hits < $1.hits }
        )
    }

    func csv() -> String {
        var s = "date,domain,hits\n"
        for r in derived.rows { s += "\(r.day),\"\(r.domain)\",\(r.hits)\n" }
        return s
    }
}
