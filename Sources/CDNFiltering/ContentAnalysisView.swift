import SwiftUI
import Charts

private enum CRTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case insights = "Insights"
    case pages = "Pages"
    case json = "JSON"
    case consumers = "Consumers"
    case excluded = "Excluded"
    var id: String { rawValue }
}

private func pct(_ v: Double) -> String { String(format: "%.1f %%", v * 100) }

struct ContentAnalysisView: View {
    @EnvironmentObject var scripts: ScriptStore
    @EnvironmentObject var sources: SourceStore
    @EnvironmentObject var model: ContentAnalysisModel
    @State private var tab = CRTab.overview
    @State private var showRules = false

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider()
            if !model.hasData {
                emptyState
            } else {
                FilterBar(model: model)
                Divider()
                Picker("", selection: $tab) {
                    ForEach(CRTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 620)
                .padding(10)
                switch tab {
                case .overview: CROverviewTab()
                case .insights: CRInsightsTab()
                case .pages: CRPagesTab()
                case .json: CRJSONTab()
                case .consumers: CRConsumersTab()
                case .excluded: CRExcludedTab()
                }
            }
        }
        .navigationTitle("Content Requests")
        .fileDropTarget(sources)
        .sheet(isPresented: $showRules) { CountingRulesSheet() }
    }

    private var sourceBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                SourceFilesView(disabled: model.isLoading)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Reuse the _analysis.tsv if it is newer", isOn: $model.reuse).font(.caption)
                    Button("How requests are counted…") { showRules = true }.buttonStyle(.link).font(.caption)
                }
                .disabled(model.isLoading)
                if model.isLoading {
                    Button(role: .destructive) { model.cancel() } label: { Label("Cancel", systemImage: "stop.fill") }
                        .controlSize(.large)
                } else {
                    Button { model.analyze(sources.urls, scripts: scripts) } label: {
                        Label(model.hasData ? "Re-analyze" : "Analyze", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(sources.urls.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            AnalysisStatusView(isLoading: model.isLoading, phase: model.phase, phaseStart: model.phaseStart,
                               error: model.errorMessage, notes: model.notes)
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.pie").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Where are your Content Requests going?").font(.title3)
            Text("Drop the raw CDN logs and press Analyze. Every line is classified as a Content Request\n(and by whom) or as excluded (and why), following Adobe's documentation.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("How requests are counted…") { showRules = true }.buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Overview

private struct CROverviewTab: View {
    @EnvironmentObject var model: ContentAnalysisModel

    var body: some View {
        let d = model.derived
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    KPI(title: "Content requests", value: Fmt.n(d.contentRequests),
                        sub: "\(Fmt.n(d.pageViews)) pages + \(Fmt.n(d.jsonCalls)) JSON ÷ \(ContentAnalysisModel.apiCallsPerContentRequest)")
                    KPI(title: "Log lines", value: Fmt.n(d.lines),
                        sub: "\(pct(d.lines > 0 ? Double(d.counted) / Double(d.lines) : 0)) counted · avg \(Fmt.n(d.days > 0 ? d.contentRequests / d.days : 0)) CR / day")
                    KPI(title: "Excluded", value: Fmt.n(d.excluded))
                    let browser = d.byClass.first { $0.key == "browser" }?.share ?? 0
                    KPI(title: "Not from browsers", value: pct(d.contentRequests > 0 ? 1 - browser : 0),
                        sub: "monitoring, bots, scripts…")
                }

                Text("From log lines to Content Requests").font(.headline)
                Chart(d.waterfall) { s in
                    BarMark(xStart: .value("From", s.from), xEnd: .value("To", s.to), y: .value("Step", s.label))
                        .foregroundStyle(by: .value("Kind", s.kind.rawValue))
                        .annotation(position: .trailing) {
                            Text(Fmt.n(s.to - s.from)).font(.caption).foregroundStyle(.secondary)
                        }
                }
                .chartForegroundStyleScale([
                    WaterfallStep.Kind.total.rawValue: Color.gray,
                    WaterfallStep.Kind.excluded.rawValue: Color.red.opacity(0.55),
                    WaterfallStep.Kind.weighting.rawValue: Color.orange.opacity(0.7),
                    WaterfallStep.Kind.result.rawValue: Color.accentColor,
                ])
                .chartYScale(domain: d.waterfall.map(\.label))
                .chartLegend(.hidden)
                .frame(height: CGFloat(d.waterfall.count) * 26 + 30)

                HStack {
                    Text("Content requests per day, by consumer").font(.headline)
                    Spacer()
                }
                Chart(d.byDayClass) { r in
                    BarMark(x: .value("Day", r.date, unit: .day), y: .value("Requests", r.hits))
                        .foregroundStyle(by: .value("Consumer", ConsumerInfo.title(r.cls)))
                }
                .chartForegroundStyleScale(domain: d.byClass.map(\.title), range: d.byClass.map { ConsumerInfo.color($0.key) })
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 260)

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("By consumer").font(.headline)
                        ForEach(d.byClass) { c in
                            ShareRow(title: c.title, hits: c.hits, share: c.share, color: ConsumerInfo.color(c.key))
                                .help(ConsumerInfo.detail(c.key))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("By response type").font(.headline)
                        ForEach(d.byType) { t in
                            ShareRow(title: t.title, hits: t.hits, share: t.share, color: .accentColor)
                        }
                        if d.jsonCalls > 0 {
                            Text("\(Fmt.n(d.jsonCalls)) JSON calls: every \(ContentAnalysisModel.apiCallsPerContentRequest) count as 1 Content Request. See the JSON tab.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Top pages").font(.headline).padding(.top, 8)
                        ForEach(d.pages.prefix(5)) { p in
                            ShareRow(title: p.path, hits: p.hits, share: p.share, color: .accentColor)
                                .help("\(p.host)\(p.path)")
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }
}

/// Label, number and a proportional bar.
private struct ShareRow: View {
    let title: String
    let hits: Int
    let share: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Fmt.n(hits)).monospacedDigit()
                Text(pct(share)).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            }
            .font(.callout)
            ShareBar(share: share, color: color)
        }
    }
}

private struct ShareBar: View {
    let share: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule().fill(color.opacity(0.8)).frame(width: max(2, g.size.width * min(share, 1)))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Insights

private struct CRInsightsTab: View {
    @EnvironmentObject var model: ContentAnalysisModel

    var body: some View {
        let insights = model.derived.insights
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Patterns in the counted requests that are often avoidable, with Adobe's recommendation for each. Percentages are of all Content Requests in the selection.")
                    .font(.callout).foregroundStyle(.secondary)
                if insights.isEmpty {
                    Label("Nothing stands out: the counted requests come from browsers.", systemImage: "checkmark.seal")
                        .padding(.top, 20)
                }
                ForEach(insights) { InsightCard(insight: $0) }
                Link("Adobe documentation: Content Requests", destination: ContentAnalysisModel.docURL).font(.callout)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }
}

private struct InsightCard: View {
    let insight: Insight

    private var color: Color {
        switch insight.level {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .info: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: insight.icon).foregroundStyle(color)
                Text(insight.title).font(.headline)
                Spacer()
                Text(Fmt.n(insight.hits)).font(.title3.weight(.semibold)).monospacedDigit()
                Text(pct(insight.share)).monospacedDigit().foregroundStyle(.secondary)
            }
            ShareBar(share: insight.share, color: color)
            Text(insight.summary).font(.callout)
            Label(insight.action, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary)
            if !insight.items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(insight.items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.label).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Spacer()
                            Text(Fmt.n(item.hits)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).fill(color).frame(width: 4)
        }
    }
}

// MARK: - Pages and JSON

/// Domain → folder → path tree. `jsonWeight` adds the Content Request equivalent of JSON calls.
private struct PathTreeView: View {
    let nodes: [PathNode]
    /// Denominator of the percentage column.
    let total: Int
    var ownLabel = "Page"
    var jsonWeight = false

    var body: some View {
        VStack(spacing: 0) {
            // Column headers, aligned with the row layout below.
            HStack(spacing: 10) {
                Text("Path")
                Spacer()
                Text(ownLabel).frame(width: 90, alignment: .trailing)
                    .help("Requests to this URL itself (\"en.html\" and \"en\" are the same node)")
                Text("Total").frame(width: 90, alignment: .trailing)
                    .help("This URL plus everything below it")
                if jsonWeight { Text("CR equiv.").frame(width: 80, alignment: .trailing) }
                Text("% of total").frame(width: 190, alignment: .trailing)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 26).padding(.vertical, 4)
            Divider()
            List(nodes, children: \.children) { node in
                HStack(spacing: 10) {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                        .help(node.urls.isEmpty ? "Folder (not requested as a page)" : node.urls.joined(separator: "\n"))
                    Spacer()
                    if node.nonBrowser > 0 {
                        Text("\(pct(Double(node.nonBrowser) / Double(max(node.hits, 1)))) non-browser")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(node.own > 0 ? Fmt.n(node.own) : "–").monospacedDigit()
                        .foregroundStyle(node.own > 0 ? Color.primary : Color.secondary)
                        .frame(width: 90, alignment: .trailing)
                    Text(Fmt.n(node.hits)).monospacedDigit().fontWeight(node.children == nil ? .regular : .semibold)
                        .frame(width: 90, alignment: .trailing)
                    if jsonWeight {
                        Text(crEquivalent(node.hits)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    let share = Double(node.hits) / Double(max(total, 1))
                    ShareBar(share: share).frame(width: 120)
                    Text(pct(share)).monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                }
            }
        }
    }
}

/// JSON calls expressed as Content Requests (5 calls = 1 Content Request), one decimal.
private func crEquivalent(_ calls: Int) -> String {
    let v = Double(calls) / Double(ContentAnalysisModel.apiCallsPerContentRequest)
    let whole = Int(v)
    let tenth = Int(((v - Double(whole)) * 10).rounded())
    return tenth == 0 ? Fmt.n(whole) : tenth == 10 ? Fmt.n(whole + 1) : "\(Fmt.n(whole)),\(tenth)"
}

/// Tree / List switch with a filter field.
private struct PathToolbar: View {
    @Binding var asTree: Bool
    @Binding var search: String
    let caption: String

    var body: some View {
        HStack {
            Picker("", selection: $asTree) {
                Text("Tree").tag(true)
                Text("List").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            if !asTree {
                TextField("Filter paths…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
            Spacer()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }
}

private struct CRPagesTab: View {
    @EnvironmentObject var model: ContentAnalysisModel
    @State private var asTree = true
    @State private var search = ""
    @State private var sort = [KeyPathComparator(\PathTotal.hits, order: .reverse)]

    var body: some View {
        let d = model.derived
        VStack(alignment: .leading, spacing: 8) {
            PathToolbar(asTree: $asTree, search: $search,
                        caption: "\(Fmt.n(d.pages.count)) pages · HTML responses (Content-Type) · query strings removed")
            if asTree {
                PathTreeView(nodes: d.pageTree, total: d.contentRequests)
            } else {
                let rows = (search.isEmpty ? d.pages : d.pages.filter { $0.path.localizedCaseInsensitiveContains(search) })
                    .sorted(using: sort)
                Table(rows, sortOrder: $sort) {
                    TableColumn("Path", value: \.path) { Text($0.path).textSelection(.enabled) }
                    TableColumn("Domain", value: \.host).width(min: 120, ideal: 170)
                    TableColumn("Page views", value: \.hits) { Text(Fmt.n($0.hits)).monospacedDigit() }.width(90)
                    TableColumn("% of CR", value: \.share) { Text(pct($0.share)).monospacedDigit() }.width(70)
                    TableColumn("Non-browser", value: \.nonBrowserShare) { p in
                        Text(pct(p.nonBrowserShare)).monospacedDigit()
                            .foregroundStyle(p.nonBrowserShare >= 0.5 ? Color.orange : Color.primary)
                    }
                    .width(90)
                }
            }
        }
    }
}

private struct CRJSONTab: View {
    @EnvironmentObject var model: ContentAnalysisModel
    @State private var asTree = false
    @State private var search = ""
    @State private var sort = [KeyPathComparator(\PathTotal.hits, order: .reverse)]

    var body: some View {
        let d = model.derived
        let ratio = ContentAnalysisModel.apiCallsPerContentRequest
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                KPI(title: "JSON calls", value: Fmt.n(d.jsonCalls))
                KPI(title: "Content requests", value: Fmt.n(d.jsonCalls / ratio),
                    sub: "\(ratio) calls = 1 · \(pct(d.contentRequests > 0 ? Double(d.jsonCalls / ratio) / Double(d.contentRequests) : 0)) of the total")
                KPI(title: "Endpoints", value: Fmt.n(d.json.filter { !$0.path.hasPrefix("(other ") }.count))
                let kinds = Dictionary(grouping: d.json, by: \.kind).mapValues { $0.reduce(0) { $0 + $1.hits } }
                let top = kinds.max { $0.value < $1.value }
                KPI(title: "Main kind", value: top?.key ?? "–",
                    sub: top.map { "\(Fmt.n($0.value)) calls" })
            }
            .padding(.horizontal, 16)

            Label("Responses whose Content-Type is JSON (application/json, application/*+json, text/json). Adobe weighs them at 1/\(ratio): every \(ratio) calls count as one Content Request in the totals.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                // No fixedSize here: outside a ScrollView it makes the minimum height explode
                // (one word per line) and the window grows past the screen.
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            if d.json.isEmpty {
                Text("No JSON responses in the selection.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PathToolbar(asTree: $asTree, search: $search,
                            caption: "\(Fmt.n(d.json.count)) endpoints · query strings removed")
                if asTree {
                    PathTreeView(nodes: d.jsonTree, total: d.jsonCalls, ownLabel: "Endpoint", jsonWeight: true)
                } else {
                    let rows = (search.isEmpty ? d.json : d.json.filter { $0.path.localizedCaseInsensitiveContains(search) })
                        .sorted(using: sort)
                    Table(rows, sortOrder: $sort) {
                        TableColumn("Endpoint", value: \.path) { Text($0.path).textSelection(.enabled).help($0.path) }
                        TableColumn("Domain", value: \.host).width(min: 120, ideal: 160)
                        TableColumn("Kind", value: \.kind).width(min: 100, ideal: 120)
                        TableColumn("Calls", value: \.hits) { Text(Fmt.n($0.hits)).monospacedDigit() }.width(80)
                        TableColumn("CR equiv.", value: \.crEquivalent) { Text(crEquivalent($0.hits)).monospacedDigit() }.width(80)
                        TableColumn("% of JSON", value: \.hits) { p in
                            Text(pct(Double(p.hits) / Double(max(d.jsonCalls, 1)))).monospacedDigit()
                        }
                        .width(80)
                        TableColumn("Non-browser", value: \.nonBrowserShare) { p in
                            Text(pct(p.nonBrowserShare)).monospacedDigit()
                                .foregroundStyle(p.nonBrowserShare >= 0.5 ? Color.orange : Color.primary)
                        }
                        .width(90)
                    }
                }
                Label("Combine calls that load the same page data, and cache JSON responses in the client when possible.",
                      systemImage: "lightbulb")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Consumers

private struct CRConsumersTab: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case agents = "User agents", ips = "Client IPs", countries = "Countries"
        var id: String { rawValue }
    }

    @EnvironmentObject var model: ContentAnalysisModel
    @State private var mode = Mode.agents
    @State private var search = ""
    @State private var uaSort = [KeyPathComparator(\UATotal.hits, order: .reverse)]
    @State private var ipSort = [KeyPathComparator(\IPTotal.hits, order: .reverse)]

    var body: some View {
        let d = model.derived
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(d.byClass) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(ConsumerInfo.color(c.key)).frame(width: 8, height: 8)
                            Text(c.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(Fmt.n(c.hits)).font(.title3.weight(.semibold)).monospacedDigit()
                        Text(pct(c.share)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    .help(ConsumerInfo.detail(c.key))
                }
            }
            .padding(.horizontal, 16)

            HStack {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        if m != .countries || !d.countries.isEmpty { Text(m.rawValue).tag(m) }
                    }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: d.countries.isEmpty ? 220 : 330)
                if mode != .countries {
                    TextField("Filter…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            switch mode {
            case .agents:
                let rows = (search.isEmpty ? d.userAgents : d.userAgents.filter { $0.ua.localizedCaseInsensitiveContains(search) })
                    .sorted(using: uaSort)
                Table(rows, sortOrder: $uaSort) {
                    TableColumn("Consumer", value: \.cls) { u in
                        HStack(spacing: 6) {
                            Circle().fill(ConsumerInfo.color(u.cls)).frame(width: 8, height: 8)
                            Text(ConsumerInfo.title(u.cls))
                        }
                    }
                    .width(min: 110, ideal: 130)
                    TableColumn("User agent", value: \.ua) { Text($0.ua.isEmpty ? "(empty)" : $0.ua).textSelection(.enabled).help($0.ua) }
                    TableColumn("Requests", value: \.hits) { Text(Fmt.n($0.hits)).monospacedDigit() }.width(90)
                    TableColumn("%", value: \.share) { Text(pct($0.share)).monospacedDigit() }.width(70)
                }
            case .ips:
                let rows = (search.isEmpty ? d.ips : d.ips.filter { $0.ip.contains(search) }).sorted(using: ipSort)
                Table(rows, sortOrder: $ipSort) {
                    TableColumn("Client IP", value: \.ip) { Text($0.ip.isEmpty ? "(empty)" : $0.ip).textSelection(.enabled) }
                    TableColumn("Requests", value: \.hits) { Text(Fmt.n($0.hits)).monospacedDigit() }.width(90)
                    TableColumn("%", value: \.share) { Text(pct($0.share)).monospacedDigit() }.width(70)
                    TableColumn("Non-browser", value: \.nonBrowserShare) { Text(pct($0.nonBrowserShare)).monospacedDigit() }.width(90)
                }
            case .countries:
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(d.countries) { c in
                            ShareRow(title: c.title.isEmpty ? "(unknown)" : c.title, hits: c.hits, share: c.share, color: .accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .onChange(of: d.countries.isEmpty) { _, empty in if empty && mode == .countries { mode = .agents } }
    }
}

// MARK: - Excluded

private struct CRExcludedTab: View {
    @EnvironmentObject var model: ContentAnalysisModel
    @State private var selection: String?

    var body: some View {
        let d = model.derived
        HSplitView {
            List(d.exclusions, selection: $selection) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(ExclusionInfo.title(e.reason)).font(.headline)
                        Spacer()
                        Text(Fmt.n(e.hits)).monospacedDigit()
                        Text(pct(e.share)).monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                    }
                    Text(ExclusionInfo.detail(e.reason)).font(.caption).foregroundStyle(.secondary)
                    ShareBar(share: e.share, color: .red)
                }
                .padding(.vertical, 3)
                .tag(e.reason)
            }
            .frame(minWidth: 280)

            VStack(alignment: .leading, spacing: 6) {
                if let r = selection, let ex = model.examples[r] {
                    Text("Top examples: \(ExclusionInfo.title(r))").font(.headline)
                    Text("Whole file, not filtered by date or domain.").font(.caption).foregroundStyle(.secondary)
                    Table(ex) {
                        TableColumn(["known-bot", "ai-crawler", "warmup"].contains(r) ? "User agent" : "Path") {
                            Text($0.text).textSelection(.enabled).help($0.text)
                        }
                        TableColumn("Domain", value: \.host).width(min: 100, ideal: 150)
                        TableColumn("Lines") { Text(Fmt.n($0.hits)).monospacedDigit() }.width(70)
                    }
                } else {
                    Text("Select a reason to see examples").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)
            .frame(minWidth: 240)
        }
        .onAppear { if selection == nil { selection = d.exclusions.first?.reason } }
    }
}

// MARK: - Rules

struct CountingRulesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let counted = [
        "GET requests with status 100–299 whose response is HTML (text/html) or JSON (application/json, application/*+json, text/json), from the CDN cache or the origin. The Content-Type decides, not the path.",
        "JSON calls weigh 1/\(ContentAnalysisModel.apiCallsPerContentRequest): every \(ContentAnalysisModel.apiCallsPerContentRequest) calls add one Content Request to the totals (Adobe's internal rule). Pages always count 1.",
        "Monitoring tools, HTTP libraries (curl, python-requests…), bots that are not on Adobe's list, and requests without a user agent.",
        "Query strings make no difference: /page.html?utm_source=x counts the same as /page.html.",
    ]
    private let excluded = [
        "3xx (including 304), 4xx and 5xx responses; methods other than GET.",
        "/libs/, /system/probes/health, /etc.clientlibs/, /api/graphql, favicon.ico and /content/experience-fragments/ (assumed same-domain: the logs have no referrer).",
        "Responses that are neither HTML nor JSON (images, CSS, JS, fonts, robots.txt…).",
        "The pod warm-up, and the well-known bots and AI crawlers listed by Adobe.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How this section counts").font(.title2.weight(.semibold))
            Text("Every line of the raw log is classified by \(ContentAnalysisModel.scriptName) (editable in Scripts) following Adobe's Content Requests documentation. Its rules are wider than clean.sh, which the Dashboard uses (that one counts only GET 200 HTML), so the totals of both sections differ.")
                .fixedSize(horizontal: false, vertical: true)
            group("Counted", "checkmark.circle.fill", .green, counted)
            group("Not counted", "xmark.circle.fill", .red, excluded)
            Text("Prefetch requests and AI agents that use a browser user agent count too, but the logs cannot tell them apart from visitors.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("Adobe documentation", destination: ContentAnalysisModel.docURL)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func group(_ title: String, _ icon: String, _ color: Color, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
    }
}
