import Foundation
import SwiftUI

// MARK: - Vocabulary shared with content-requests.sh

/// The kinds of client behind a counted Content Request (`class` column of the script output).
enum ConsumerInfo {
    static let order = ["browser", "monitoring", "http-library", "unclassified-bot", "empty-ua"]

    static func title(_ c: String) -> String {
        switch c {
        case "browser": return "Browsers"
        case "monitoring": return "Monitoring tools"
        case "http-library": return "HTTP libraries"
        case "unclassified-bot": return "Unlisted bots"
        case "empty-ua": return "No user agent"
        default: return c
        }
    }

    static func detail(_ c: String) -> String {
        switch c {
        case "browser": return "Regular browser user agents: real visitors, or automation that presents itself as a browser."
        case "monitoring": return "Uptime and health checkers (UptimeRobot, Site24x7, Route53…) requesting pages. Adobe counts them."
        case "http-library": return "curl, python-requests, Go, Java, axios… Adobe counts requests from HTTP libraries."
        case "unclassified-bot": return "Look automated but are not on Adobe's list of well-known bots, so they count."
        case "empty-ua": return "Requests without a user agent. They count and cannot be recognised as bots."
        default: return "Class produced by a customised content-requests.sh."
        }
    }

    static func color(_ c: String) -> Color {
        switch c {
        case "browser": return .blue
        case "monitoring": return .orange
        case "http-library": return .purple
        case "unclassified-bot": return .red
        case "empty-ua": return .gray
        default: return .teal
        }
    }
}

/// Why a log line is not a Content Request (`reason` column of the script output).
enum ExclusionInfo {
    static func title(_ r: String) -> String {
        switch r {
        case "method": return "Not GET (HEAD, POST…)"
        case "3xx": return "Redirects and 304 (3xx)"
        case "4xx": return "Client errors (4xx)"
        case "5xx": return "Server errors (5xx)"
        case "other-status": return "Other status codes"
        case "libs": return "/libs/ (AEM internals)"
        case "health-probe": return "/system/probes/health"
        case "clientlibs": return "/etc.clientlibs/"
        case "graphql": return "/api/graphql (Commerce)"
        case "favicon": return "favicon.ico"
        case "xf": return "Experience fragments"
        case "static-asset": return "Static assets"
        case "other-type": return "Other response types"
        case "warmup": return "Pod warm-up"
        case "known-bot": return "Well-known bots"
        case "ai-crawler": return "Well-known AI crawlers"
        case "unparsed": return "Unrecognised lines"
        default: return r
        }
    }

    static func detail(_ r: String) -> String {
        switch r {
        case "method": return "This analysis only counts GET. Adobe recommends HEAD for availability checks."
        case "3xx": return "Redirects and conditional responses carry no content."
        case "4xx": return "Not found and other request errors."
        case "5xx": return "Errors returned by AEM or custom code."
        case "other-status": return "Status codes outside 100–599."
        case "libs": return "AEM internal JSON such as the CSRF token."
        case "health-probe": return "The path Adobe recommends for availability monitoring."
        case "clientlibs": return "Platform client libraries and runtime configuration."
        case "graphql": return "Commerce Integration Framework calls, excluded to avoid double counting."
        case "favicon": return "Excluded explicitly, even when served as HTML."
        case "xf": return "Excluded when reused on the same domain. The logs carry no referrer, so every /content/experience-fragments/ request is assumed to be same-domain."
        case "static-asset": return "Images, video, CSS, JS, fonts and PDF: neither HTML nor JSON."
        case "other-type": return "Responses that are neither HTML nor JSON (robots.txt, sitemap.xml, text/plain…)."
        case "warmup": return "AEM as a Cloud Service pod warm-up (skyline-service-warmup)."
        case "known-bot": return "Search engines, social networks and SEO crawlers tagged by the CDN."
        case "ai-crawler": return "AI / LLM crawlers tagged by the CDN."
        case "unparsed": return "Lines in neither the legacy CSV layout nor JSON."
        default: return "Reason produced by a customised content-requests.sh."
        }
    }
}

// MARK: - Raw rows (as read from the script output)

private struct SRow { let day, host: String; let counted: Bool; let reason, type: String; let hits: Int }
private struct PRow { let day, host, path, type: String; let hits, nonBrowser: Int }
private struct URow { let day, host, cls, ua: String; let hits: Int }
private struct IRow { let day, host, ip: String; let hits, nonBrowser: Int }
private struct GRow { let day, host, country: String; let hits: Int }

// MARK: - Aggregates shown in the UI

struct NamedTotal: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let title: String
    let hits: Int
    let share: Double
}

struct DayClass: Identifiable {
    var id: String { day + "|" + cls }
    let day: String
    let date: Date
    let cls: String
    /// Content Requests, with JSON calls weighted at 1/5 (so it can be fractional).
    let hits: Double
}

struct WaterfallStep: Identifiable {
    enum Kind: String { case total = "Log lines", excluded = "Excluded", weighting = "JSON weighting", result = "Content requests" }
    var id: String { label }
    let label: String
    let from: Int
    let to: Int
    let kind: Kind
}

/// A path with one response type ("html" or "json", from the Content-Type of the response).
struct PathTotal: Identifiable {
    var id: String { type + "\t" + host + path }
    let host: String
    let path: String
    let type: String
    let hits: Int
    let nonBrowser: Int
    /// Share of all Content Requests in the selection.
    let share: Double
    var nonBrowserShare: Double { hits > 0 ? Double(nonBrowser) / Double(hits) : 0 }
    /// Content Requests this path is worth once JSON calls are weighted (1 / `apiCallsPerContentRequest`).
    var crEquivalent: Double {
        type == "json" ? Double(hits) / Double(ContentAnalysisModel.apiCallsPerContentRequest) : Double(hits)
    }
    /// What kind of JSON endpoint this looks like, from the path. Only used for grouping: the
    /// type itself comes from the Content-Type.
    var kind: String {
        let p = path.lowercased()
        if p.contains("/graphql/execute.json/") { return "Persisted query" }
        if p.hasSuffix(".model.json") { return "Sling model" }
        if p.hasSuffix(".json") { return "Other .json" }
        return "No .json extension"
    }
}

/// A node in the domain → folder → page tree.
/// A node in the domain → folder → page tree. A page and the folder of the same name
/// (`/en.html` and `/en/…`) share one node: `own` counts the page itself, `hits` the page plus
/// everything below it.
struct PathNode: Identifiable {
    let id: String
    let name: String
    /// Total: the node's own page plus all its descendants.
    var hits: Int
    var nonBrowser: Int
    /// Requests to the node's own URL(s); 0 for folders that are not a page.
    var own: Int
    /// The URLs counted in `own` (e.g. "/en.html", or "/en" and "/en.html" if both appear).
    var urls: [String]
    var children: [PathNode]?
}

struct UATotal: Identifiable {
    var id: String { cls + "\t" + ua }
    let cls: String
    let ua: String
    let hits: Int
    let share: Double
}

struct IPTotal: Identifiable {
    var id: String { ip }
    let ip: String
    let hits: Int
    let nonBrowser: Int
    let share: Double
    var nonBrowserShare: Double { hits > 0 ? Double(nonBrowser) / Double(hits) : 0 }
}

struct ExclusionTotal: Identifiable {
    var id: String { reason }
    let reason: String
    let hits: Int
    let share: Double
}

struct Example: Identifiable {
    var id: String { host + "\t" + text }
    let host: String
    let text: String
    let hits: Int
}

struct Insight: Identifiable {
    enum Level: Int { case info, low, medium, high }
    let id: String
    let title: String
    let icon: String
    let hits: Int
    let share: Double
    let summary: String
    let action: String
    let items: [(label: String, hits: Int)]

    var level: Level { share >= 0.05 ? .high : share >= 0.01 ? .medium : .low }
}

struct CRDerived {
    var lines = 0
    /// Log lines that are Content Requests (HTML pages + JSON calls), before weighting.
    var counted = 0
    var excluded: Int { lines - counted }
    /// Content Requests: every HTML page counts 1, JSON calls count 1 per complete group of 5.
    var contentRequests = 0
    var waterfall: [WaterfallStep] = []
    var byClass: [NamedTotal] = []
    var byType: [NamedTotal] = []
    var byDayClass: [DayClass] = []
    /// HTML responses (pages).
    var pages: [PathTotal] = []
    var pageTree: [PathNode] = []
    var pageViews = 0
    /// JSON responses (API calls).
    var json: [PathTotal] = []
    var jsonTree: [PathNode] = []
    var jsonCalls = 0
    var jsonCREquivalent: Double { Double(jsonCalls) / Double(ContentAnalysisModel.apiCallsPerContentRequest) }
    var userAgents: [UATotal] = []
    var ips: [IPTotal] = []
    var countries: [NamedTotal] = []
    var exclusions: [ExclusionTotal] = []
    var insights: [Insight] = []
    var days = 0
}

// MARK: - Model

@MainActor
final class ContentAnalysisModel: DateDomainFilterable {
    static let scriptName = "content-requests.sh"
    /// Adobe counts JSON calls at 1/5: five of them make one Content Request.
    nonisolated static let apiCallsPerContentRequest = 5
    static let docURL = URL(string: "https://experienceleague.adobe.com/en/docs/experience-manager-cloud-service/content/implementing/using-cloud-manager/content-requests")!

    @Published var reuse = true

    @Published var isLoading = false
    @Published var phase = ""
    @Published var phaseStart: Date?
    @Published var errorMessage: String?
    @Published var notes: [String] = []

    @Published private(set) var hasData = false
    @Published private(set) var allDomains: [DomainTotal] = []
    @Published private(set) var minDate = Date()
    @Published private(set) var maxDate = Date()
    /// Top excluded examples per reason, for the whole file (not filtered).
    @Published private(set) var examples: [String: [Example]] = [:]

    @Published var start = Date() { didSet { recompute() } }
    @Published var end = Date() { didSet { recompute() } }
    @Published var selectedDomains: Set<String> = [] { didSet { recompute() } }

    @Published private(set) var derived = CRDerived()

    let exportName = "content-requests.csv"

    private var sRows: [SRow] = []
    private var pRows: [PRow] = []
    private var uRows: [URow] = []
    private var iRows: [IRow] = []
    private var gRows: [GRow] = []

    private let shell = ShellExec()
    private var cancelled = false
    private var suspendRecompute = false

    func analysisURL(for src: URL) -> URL {
        URL(fileURLWithPath: src.deletingPathExtension().path + "_analysis.tsv")
    }

    func cancel() {
        cancelled = true
        shell.cancel()
    }

    func analyze(_ sources: [URL], scripts: ScriptStore) {
        guard !isLoading, !sources.isEmpty else { return }
        guard scripts.exists(Self.scriptName) else {
            errorMessage = "Script \(Self.scriptName) not found in the scripts folder (use \"Reset to default\" in Scripts)."
            return
        }
        isLoading = true
        cancelled = false
        errorMessage = nil
        notes = []
        let script = scripts.url(Self.scriptName)

        Task { [weak self] in
            guard let self else { return }
            var outputs: [URL] = []
            var failure: String?

            for (i, src) in sources.enumerated() {
                if self.cancelled { break }
                if src.lastPathComponent.contains("_clean") {
                    self.notes.append("\(src.lastPathComponent) looks like a clean.sh output: this section needs the raw log to show what is excluded.")
                }
                let tag = sources.count > 1 ? " (\(i + 1)/\(sources.count))" : ""
                let target = self.analysisURL(for: src)
                if self.reuse && DashboardModel.isFresh(target, comparedTo: src, script) {
                    self.notes.append("\(target.lastPathComponent): reused (newer than the log and the script)")
                } else {
                    self.phase = "Classifying \(src.lastPathComponent)\(tag)"
                    self.phaseStart = Date()
                    let out = DataCollector()
                    let code = await self.shell.run("/bin/bash", [script.path, src.path, target.path],
                                                    cwd: scripts.directory, onOutput: { out.append($0) })
                    if self.cancelled { break }
                    if code != 0 { failure = "\(Self.scriptName) failed on \(src.lastPathComponent): \(out.text)"; break }
                    self.notes.append(out.text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                outputs.append(target)
            }

            if !self.cancelled && failure == nil {
                self.phase = "Reading results"
                self.phaseStart = Date()
                failure = self.load(outputs)
            }
            self.isLoading = false
            self.phaseStart = nil
            if self.cancelled { self.notes.append("Analysis cancelled.") }
            if let failure { self.errorMessage = failure }
        }
    }

    // MARK: Loading

    /// Parses the script outputs. Returns an error message, or nil.
    private func load(_ files: [URL]) -> String? {
        var s: [SRow] = [], p: [PRow] = [], u: [URow] = [], ip: [IRow] = [], g: [GRow] = []
        var ex: [String: [String: Int]] = [:]
        var invalid = 0

        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                return "Cannot read \(file.lastPathComponent)"
            }
            for line in text.split(separator: "\n") {
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                switch f.first {
                case "S" where f.count == 7:
                    if let n = Int(f[6]) { s.append(SRow(day: f[1], host: f[2], counted: f[3] == "C", reason: f[4], type: f[5], hits: n)) }
                case "P" where f.count == 7:
                    if let n = Int(f[5]), let nb = Int(f[6]) { p.append(PRow(day: f[1], host: f[2], path: f[3], type: f[4], hits: n, nonBrowser: nb)) }
                case "U" where f.count == 6:
                    if let n = Int(f[5]) { u.append(URow(day: f[1], host: f[2], cls: f[3], ua: f[4], hits: n)) }
                case "I" where f.count == 6:
                    if let n = Int(f[4]), let nb = Int(f[5]) { ip.append(IRow(day: f[1], host: f[2], ip: f[3], hits: n, nonBrowser: nb)) }
                case "G" where f.count == 5:
                    if let n = Int(f[4]) { g.append(GRow(day: f[1], host: f[2], country: f[3], hits: n)) }
                case "E" where f.count == 5:
                    if let n = Int(f[4]) { ex[f[1], default: [:]][f[2] + "\t" + f[3], default: 0] += n }
                case "#invalid" where f.count == 2:
                    invalid += Int(f[1]) ?? 0
                default:
                    break
                }
            }
        }
        guard !s.isEmpty else { return "No log lines were recognised." }
        if invalid > 0 { notes.append("\(Fmt.n(invalid)) lines without a valid date ignored.") }

        sRows = s; pRows = p; uRows = u; iRows = ip; gRows = g
        examples = ex.mapValues { dict in
            dict.map { k, v -> Example in
                let parts = k.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                return Example(host: String(parts[0]), text: parts.count > 1 ? String(parts[1]) : "", hits: v)
            }.sorted { $0.hits > $1.hits }
        }

        suspendRecompute = true
        var totals: [String: Int] = [:]
        for r in s { totals[r.host, default: 0] += r.counted ? r.hits : 0 }
        let sum = max(totals.values.reduce(0, +), 1)
        allDomains = totals.map { DomainTotal(domain: $0.key, hits: $0.value, share: Double($0.value) / Double(sum)) }
            .sorted { ($0.hits, $1.domain) > ($1.hits, $0.domain) }
        let days = Set(s.map(\.day)).sorted()
        minDate = days.first.flatMap { Fmt.day.date(from: $0) } ?? Date()
        maxDate = days.last.flatMap { Fmt.day.date(from: $0) } ?? Date()
        start = minDate
        end = maxDate
        selectedDomains = Set(totals.keys)
        hasData = true
        suspendRecompute = false
        recompute()
        return nil
    }

    // MARK: Filters

    func resetFilters() {
        suspendRecompute = true
        start = minDate
        end = maxDate
        selectedDomains = Set(allDomains.map(\.domain))
        suspendRecompute = false
        recompute()
    }

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
        guard !suspendRecompute, hasData else { return }
        let lo = Fmt.day.string(from: start), hi = Fmt.day.string(from: end)
        let hosts = selectedDomains
        func keep(_ day: String, _ host: String) -> Bool { day >= lo && day <= hi && hosts.contains(host) }

        var d = CRDerived()

        // Lines, classes, types, exclusions, per day.
        // Class and day breakdowns weigh JSON calls at 1/5 so they add up to the Content Requests.
        let ratio = Self.apiCallsPerContentRequest
        var byClass: [String: Double] = [:], byType: [String: Int] = [:], byReason: [String: Int] = [:]
        var dayClass: [String: Double] = [:], days = Set<String>()
        for r in sRows where keep(r.day, r.host) {
            d.lines += r.hits
            days.insert(r.day)
            if r.counted {
                d.counted += r.hits
                let w = r.type == "json" ? Double(r.hits) / Double(ratio) : Double(r.hits)
                // For counted lines the reason column holds the consumer class.
                byClass[r.reason, default: 0] += w
                byType[r.type, default: 0] += r.hits
                dayClass[r.day + "\t" + r.reason, default: 0] += w
            } else {
                byReason[r.reason, default: 0] += r.hits
            }
        }
        d.days = days.count
        d.pageViews = byType["html"] ?? 0
        d.jsonCalls = byType["json"] ?? 0
        d.contentRequests = d.pageViews + d.jsonCalls / ratio
        let crTotal = Double(max(d.contentRequests, 1)), lines = max(d.lines, 1)
        /// Share of the Content Requests (weighted).
        func share(_ n: Double) -> Double { n / crTotal }
        func share(_ n: Int) -> Double { Double(n) / crTotal }
        /// Share of the counted requests (unweighted), for user agents and IPs, which mix both types.
        func shareOfRequests(_ n: Int) -> Double { Double(n) / Double(max(d.counted, 1)) }

        let classOrder = ConsumerInfo.order + byClass.keys.filter { !ConsumerInfo.order.contains($0) }.sorted()
        d.byClass = classOrder.compactMap { c in
            byClass[c].map { NamedTotal(key: c, title: ConsumerInfo.title(c), hits: Int($0.rounded()), share: share($0)) }
        }
        d.byType = byType.sorted { $0.value > $1.value }.map { k, v in
            let cr = k == "json" ? v / ratio : v
            return NamedTotal(key: k, title: k == "html" ? "HTML pages" : k == "json" ? "JSON calls ÷ \(ratio)" : k.uppercased(),
                              hits: cr, share: share(cr))
        }
        d.byDayClass = dayClass.compactMap { k, v -> DayClass? in
            let p = k.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let date = Fmt.day.date(from: String(p[0])) else { return nil }
            return DayClass(day: String(p[0]), date: date, cls: String(p[1]), hits: v)
        }
        d.exclusions = byReason.sorted { $0.value > $1.value }.map {
            ExclusionTotal(reason: $0.key, hits: $0.value, share: Double($0.value) / Double(lines))
        }

        // Waterfall: all lines, minus each exclusion reason, down to the content requests.
        var steps = [WaterfallStep(label: "All log lines", from: 0, to: d.lines, kind: .total)]
        var level = d.lines
        let maxSteps = 9
        for (i, e) in d.exclusions.enumerated() {
            if i == maxSteps - 1 && d.exclusions.count > maxSteps {
                let rest = d.exclusions[i...].reduce(0) { $0 + $1.hits }
                steps.append(WaterfallStep(label: "− Other exclusions", from: level - rest, to: level, kind: .excluded))
                level -= rest
                break
            }
            steps.append(WaterfallStep(label: "− " + ExclusionInfo.title(e.reason), from: level - e.hits, to: level, kind: .excluded))
            level -= e.hits
        }
        let discount = d.counted - d.contentRequests
        if discount > 0 {
            steps.append(WaterfallStep(label: "− JSON calls (\(ratio) calls = 1)", from: level - discount, to: level, kind: .weighting))
        }
        steps.append(WaterfallStep(label: "Content requests", from: 0, to: d.contentRequests, kind: .result))
        d.waterfall = steps

        // Paths, split by response type.
        var paths: [String: (hits: Int, nb: Int)] = [:]
        for r in pRows where keep(r.day, r.host) {
            let k = r.type + "\t" + r.host + "\t" + r.path
            let v = paths[k] ?? (0, 0)
            paths[k] = (v.hits + r.hits, v.nb + r.nonBrowser)
        }
        let all = paths.map { k, v in
            let p = k.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            let cr = p[0] == "json" ? Double(v.hits) / Double(ratio) : Double(v.hits)
            return PathTotal(host: p[1], path: p.count > 2 ? p[2] : "", type: p[0], hits: v.hits, nonBrowser: v.nb, share: share(cr))
        }.sorted { ($0.hits, $1.id) > ($1.hits, $0.id) }.foldedLast(\.path)
        d.pages = all.filter { $0.type == "html" }
        d.json = all.filter { $0.type == "json" }
        d.pageTree = Self.buildTree(d.pages)
        d.jsonTree = Self.buildTree(d.json)

        // User agents, IPs, countries.
        var uas: [String: Int] = [:]
        for r in uRows where keep(r.day, r.host) { uas[r.cls + "\t" + r.ua, default: 0] += r.hits }
        d.userAgents = uas.map { k, v in
            let p = k.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            return UATotal(cls: String(p[0]), ua: p.count > 1 ? String(p[1]) : "", hits: v, share: shareOfRequests(v))
        }.sorted { ($0.hits, $1.id) > ($1.hits, $0.id) }.foldedLast(\.ua)

        var ips: [String: (Int, Int)] = [:]
        for r in iRows where keep(r.day, r.host) {
            let v = ips[r.ip] ?? (0, 0)
            ips[r.ip] = (v.0 + r.hits, v.1 + r.nonBrowser)
        }
        d.ips = ips.map { IPTotal(ip: $0.key, hits: $0.value.0, nonBrowser: $0.value.1, share: shareOfRequests($0.value.0)) }
            .sorted { ($0.hits, $1.ip) > ($1.hits, $0.ip) }.foldedLast(\.ip)

        var countries: [String: Int] = [:]
        for r in gRows where keep(r.day, r.host) { countries[r.country, default: 0] += r.hits }
        d.countries = countries.sorted { $0.value > $1.value }.map {
            NamedTotal(key: $0.key, title: $0.key, hits: $0.value, share: shareOfRequests($0.value))
        }

        d.insights = Self.insights(d)
        derived = d
    }

    /// "en.html" → "en", so a page and its folder share a tree node. Other names are unchanged.
    nonisolated static func pageKey(_ segment: String) -> String {
        for ext in [".html", ".htm"] where segment.count > ext.count && segment.lowercased().hasSuffix(ext) {
            return String(segment.dropLast(ext.count))
        }
        return segment
    }

    nonisolated fileprivate static func isFolded(_ s: String) -> Bool { s.hasPrefix("(other ") && s.hasSuffix(")") }

    private static func buildTree(_ paths: [PathTotal]) -> [PathNode] {
        final class Box {
            var hits = 0, nb = 0, own = 0
            var urls = Set<String>()
            var children: [String: Box] = [:]
        }
        var roots: [String: Box] = [:]
        for p in paths {
            let root = roots[p.host] ?? Box()
            roots[p.host] = root
            root.hits += p.hits; root.nb += p.nonBrowser
            var node = root
            let parts = p.path == "/" ? ["/"] : p.path.split(separator: "/").map(String.init)
            for (i, part) in parts.enumerated() {
                let isLast = i == parts.count - 1
                // The last segment is the page: "en.html" joins the "en" folder node.
                let key = isLast ? pageKey(part) : part
                let child = node.children[key] ?? Box()
                node.children[key] = child
                child.hits += p.hits; child.nb += p.nonBrowser
                if isLast { child.own += p.hits; child.urls.insert(p.path) }
                node = child
            }
        }
        func convert(_ name: String, _ id: String, _ box: Box) -> PathNode {
            let kids = box.children.map { convert($0.key, id + "/" + $0.key, $0.value) }
                .sorted { ($0.hits, $1.name) > ($1.hits, $0.name) }
            return PathNode(id: id, name: name, hits: box.hits, nonBrowser: box.nb, own: box.own,
                            urls: box.urls.sorted(), children: kids.isEmpty ? nil : kids)
        }
        return roots.map { convert($0.key.isEmpty ? "(no domain)" : $0.key, $0.key, $0.value) }
            .sorted { ($0.hits, $1.name) > ($1.hits, $0.name) }
    }

    // MARK: Insights

    private static let softNotFound = try! NSRegularExpression(pattern: #"(^|[/._-])(404|not-?found|page-?not-?found|error|errors)([/._-]|$)"#, options: [.caseInsensitive])

    private static func insights(_ d: CRDerived) -> [Insight] {
        guard d.contentRequests > 0 else { return [] }
        let total = Double(d.contentRequests)
        var out: [Insight] = []
        func classHits(_ c: String) -> Int { d.byClass.first { $0.key == c }?.hits ?? 0 }
        func topUAs(_ c: String) -> [(String, Int)] {
            d.userAgents.filter { $0.cls == c }.prefix(5).map { ($0.ua.isEmpty ? "(empty)" : $0.ua, $0.hits) }
        }
        func add(_ id: String, _ title: String, _ icon: String, _ hits: Int, _ summary: String, _ action: String, _ items: [(String, Int)]) {
            guard hits > 0 else { return }
            out.append(Insight(id: id, title: title, icon: icon, hits: hits, share: Double(hits) / total,
                               summary: summary, action: action, items: items.map { (label: $0.0, hits: $0.1) }))
        }

        add("monitoring", "Monitoring tools requesting pages", "waveform.path.ecg", classHits("monitoring"),
            "Uptime and health checkers that fetch real pages count as Content Requests on every check.",
            "Point them to /system/probes/health (not counted) or switch them to HEAD requests, and lower their frequency.",
            topUAs("monitoring"))
        add("bots", "Bots not on Adobe's exclusion list", "ant", classHits("unclassified-bot"),
            "These user agents look automated but are not among the well-known bots Adobe excludes, so they are billed.",
            "Check whether you need them. Block or rate-limit them with CDN traffic filter rules (user agent, AS name, country).",
            topUAs("unclassified-bot"))
        add("libraries", "HTTP libraries and scripts", "terminal", classHits("http-library"),
            "Requests from curl, python-requests, Go, Java and similar clients count as Content Requests.",
            "Identify the integrations behind them. If they are yours, reduce or cache their calls; otherwise filter them.",
            topUAs("http-library"))
        add("empty-ua", "Requests without a user agent", "questionmark.circle", classHits("empty-ua"),
            "Without a user agent the CDN cannot recognise a bot, so these requests count.",
            "Block missing or empty user agents with a traffic filter rule. If a proxy or CDN sits in front of AEM, make sure it forwards the browser user agent.",
            topUAs("empty-ua"))

        // Browser traffic only: monitoring, bots and scripts already have their own insight.
        let heavy = d.ips.filter { !$0.ip.isEmpty && !$0.ip.hasPrefix("(other ") && Double($0.hits - $0.nonBrowser) / total >= 0.02 }
            .sorted { $0.hits - $0.nonBrowser > $1.hits - $1.nonBrowser }
        add("ips", "Browser traffic concentrated on a few IPs", "network", heavy.reduce(0) { $0 + $1.hits - $1.nonBrowser },
            "Each of these client IPs makes at least 2% of all Content Requests with a browser user agent. Scrapers and AI agents often pretend to be a browser, so only the volume gives them away.",
            "Check who they are (office proxy, partner, scraper). Rate-limit or block unknown ones with traffic filter rules.",
            heavy.prefix(5).map { ($0.ip, $0.hits - $0.nonBrowser) })

        let soft = d.pages.filter { p in
            softNotFound.firstMatch(in: p.path, range: NSRange(p.path.startIndex..., in: p.path)) != nil
        }
        add("soft404", "Error pages answered with 200", "exclamationmark.triangle", soft.reduce(0) { $0 + $1.hits },
            "Pages that look like \"not found\" or error pages but return 200 count as Content Requests; a real 404 does not.",
            "Return a real 404 (or 410) status for missing content, and use server-side 301/302 redirects instead of JavaScript redirects.",
            soft.prefix(5).map { ("\($0.host)\($0.path)", $0.hits) })

        return out.sorted { ($0.level.rawValue, $0.hits) > ($1.level.rawValue, $1.hits) }
    }

    // MARK: Export

    func csv() -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var s = "domain,path,type,requests,non_browser,share,cr_equivalent\n"
        for p in derived.pages + derived.json {
            s += "\(q(p.host)),\(q(p.path)),\(p.type),\(p.hits),\(p.nonBrowser),\(String(format: "%.4f", p.share)),\(String(format: "%.1f", p.crEquivalent))\n"
        }
        return s
    }
}


private extension Array {
    /// Moves the "(other …)" rows that content-requests.sh folds the long tail into to the end.
    func foldedLast(_ key: KeyPath<Element, String>) -> [Element] {
        filter { !ContentAnalysisModel.isFolded($0[keyPath: key]) } + filter { ContentAnalysisModel.isFolded($0[keyPath: key]) }
    }
}
