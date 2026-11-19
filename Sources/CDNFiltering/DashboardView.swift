import SwiftUI
import Charts

private enum DashTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case domains = "Domains"
    case detail = "Day × domain"
    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject var scripts: ScriptStore
    @EnvironmentObject var sources: SourceStore
    @EnvironmentObject var model: DashboardModel
    @State private var tab = DashTab.summary

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider()
            if model.allRows.isEmpty {
                emptyState
            } else {
                FilterBar(model: model)
                Divider()
                Picker("", selection: $tab) {
                    ForEach(DashTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                .padding(10)
                switch tab {
                case .summary: SummaryTab()
                case .domains: DomainsTab()
                case .detail: DetailTab()
                }
            }
        }
        .navigationTitle("Dashboard")
        .fileDropTarget(sources)
        .onChange(of: sources.urls) { _, urls in model.sourcesChanged(urls) }
    }

    // MARK: Sources

    private var sourceBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                SourceFilesView(disabled: model.isLoading)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: $model.cleanFirst) {
                        Text("Clean and analyze").tag(true)
                        Text("Already clean").tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    if model.cleanFirst {
                        Toggle("Reuse the _clean.csv if it exists and is newer", isOn: $model.reuseClean)
                            .font(.caption)
                    }
                }
                .disabled(model.isLoading)
                if model.isLoading {
                    Button(role: .destructive) { model.cancel() } label: { Label("Cancel", systemImage: "stop.fill") }
                        .controlSize(.large)
                } else {
                    Button { model.analyze(sources.urls, scripts: scripts) } label: {
                        Label(model.allRows.isEmpty ? "Analyze" : "Re-analyze", systemImage: "play.fill")
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
            Image(systemName: "chart.bar.xaxis").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Drop your logs and press Analyze").font(.title3)
            Text("They are cleaned with clean.sh (optional) and counted in a single pass, then\nyou can filter by date and domain instantly.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filters

struct FilterBar<Model: DateDomainFilterable>: View {
    @ObservedObject var model: Model
    @State private var showDomains = false

    var body: some View {
        HStack(spacing: 12) {
            DatePicker("From", selection: $model.start, in: model.minDate...model.maxDate, displayedComponents: .date)
            DatePicker("To", selection: $model.end, in: model.minDate...model.maxDate, displayedComponents: .date)
            Menu("Shortcuts") {
                Button("Entire period") { model.setLastDays(nil) }
                Button("Last 7 days") { model.setLastDays(7) }
                Button("Last 14 days") { model.setLastDays(14) }
                Button("Last 30 days") { model.setLastDays(30) }
            }
            .fixedSize()
            Button {
                showDomains.toggle()
            } label: {
                Label("Domains: \(model.selectedDomains.count) of \(model.allDomains.count)", systemImage: "line.3.horizontal.decrease.circle")
            }
            .popover(isPresented: $showDomains, arrowEdge: .bottom) { DomainPicker(model: model).frame(width: 380, height: 440) }
            Button("Reset") { model.resetFilters() }
            Spacer()
            Button { export() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .overlay(alignment: .bottomTrailing) {
            if model.start > model.end {
                Text("Start is after end").font(.caption).foregroundStyle(.red).padding(.trailing, 12)
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.exportName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.csv().write(to: url, atomically: true, encoding: .utf8)
    }
}

struct DomainPicker<Model: DateDomainFilterable>: View {
    @ObservedObject var model: Model
    @State private var search = ""

    private var visible: [DomainTotal] {
        search.isEmpty ? model.allDomains : model.allDomains.filter { $0.domain.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search domain…", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Button("Select \(search.isEmpty ? "all" : "visible")") {
                    model.selectedDomains.formUnion(visible.map(\.domain))
                }
                Button("Deselect \(search.isEmpty ? "all" : "visible")") {
                    model.selectedDomains.subtract(visible.map(\.domain))
                }
                Button("Only visible") { model.selectedDomains = Set(visible.map(\.domain)) }
                    .disabled(search.isEmpty)
                Spacer()
            }
            .font(.caption)
            List(visible) { d in
                Toggle(isOn: Binding(
                    get: { model.selectedDomains.contains(d.domain) },
                    set: { on in
                        if on { model.selectedDomains.insert(d.domain) } else { model.selectedDomains.remove(d.domain) }
                    })) {
                    HStack {
                        Text(d.domain.isEmpty ? "(empty)" : d.domain).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Fmt.n(d.hits)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Tabs

struct KPI: View {
    let title: String
    let value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit()
            if let sub { Text(sub).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

struct SummaryTab: View {
    @EnvironmentObject var model: DashboardModel
    @State private var stacked = true

    var body: some View {
        let d = model.derived
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    KPI(title: "Requests", value: Fmt.n(d.total))
                    KPI(title: "Days", value: "\(d.byDay.count)",
                        sub: d.byDay.isEmpty ? nil : "avg \(Fmt.n(d.total / max(d.byDay.count, 1))) / day")
                    KPI(title: "Domains", value: "\(d.byDomain.count)")
                    KPI(title: "Peak day", value: d.peakDay.map { Fmt.n($0.hits) } ?? "–", sub: d.peakDay?.day)
                }

                HStack {
                    Text("Requests per day").font(.headline)
                    Spacer()
                    Toggle("Stack by domain (top \(Derived.stackTop))", isOn: $stacked).toggleStyle(.switch)
                }
                Chart {
                    if stacked {
                        ForEach(d.stack) { r in
                            BarMark(x: .value("Day", r.date, unit: .day), y: .value("Requests", r.hits))
                                .foregroundStyle(by: .value("Domain", r.domain))
                        }
                    } else {
                        ForEach(d.byDay) { r in
                            BarMark(x: .value("Day", r.date, unit: .day), y: .value("Requests", r.hits))
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 280)

                Text("Top domains by requests").font(.headline)
                let top = Array(d.byDomain.prefix(12))
                Chart(top) { r in
                    BarMark(x: .value("Requests", r.hits), y: .value("Domain", r.domain))
                        .annotation(position: .trailing) { Text(Fmt.n(r.hits)).font(.caption).foregroundStyle(.secondary) }
                }
                .chartYScale(domain: top.map(\.domain))
                .frame(height: CGFloat(max(top.count, 1)) * 28 + 20)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }
}

struct DomainsTab: View {
    @EnvironmentObject var model: DashboardModel
    @State private var sort = [KeyPathComparator(\DomainTotal.hits, order: .reverse)]

    var body: some View {
        Table(model.derived.byDomain.sorted(using: sort), sortOrder: $sort) {
            TableColumn("Domain", value: \.domain)
            TableColumn("Requests", value: \.hits) { Text(Fmt.n($0.hits)).monospacedDigit() }
                .width(120)
            TableColumn("%", value: \.share) { Text(String(format: "%.1f %%", $0.share * 100)).monospacedDigit() }
                .width(80)
        }
    }
}

struct DetailTab: View {
    @EnvironmentObject var model: DashboardModel
    @State private var sort = [KeyPathComparator(\HitRow.day), KeyPathComparator(\HitRow.hits, order: .reverse)]

    var body: some View {
        let d = model.derived
        VStack(alignment: .leading, spacing: 8) {
            Text("Heatmap: top \(Derived.heatTop) domains").font(.headline).padding(.horizontal, 16)
            Chart(d.heat) { r in
                RectangleMark(x: .value("Day", r.day), y: .value("Domain", r.domain))
                    .foregroundStyle(by: .value("Requests", r.hits))
            }
            .chartForegroundStyleScale(range: Gradient(colors: [Color.blue.opacity(0.15), Color.blue]))
            .frame(height: 240)
            .padding(.horizontal, 16)

            Table(d.rows.sorted(using: sort), sortOrder: $sort) {
                TableColumn("Date", value: \.day).width(110)
                TableColumn("Domain", value: \.domain)
                TableColumn("Requests", value: \.hits) { Text(Fmt.n($0.hits)).monospacedDigit() }.width(120)
            }
        }
    }
}
