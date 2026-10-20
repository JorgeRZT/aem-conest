import SwiftUI

@main
struct AEMConestApp: App {
    @StateObject private var scripts = ScriptStore()
    @StateObject private var flow = FlowStore()
    @StateObject private var runner = Runner()
    @StateObject private var dashboard = DashboardModel()
    @StateObject private var updates = UpdateChecker()

    var body: some Scene {
        WindowGroup("AEM Conest") {
            ContentView()
                .environmentObject(scripts)
                .environmentObject(flow)
                .environmentObject(runner)
                .environmentObject(dashboard)
                .environmentObject(updates)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About AEM Conest") { showAboutPanel() }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updates.check(manual: true) } }
            }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case process = "Process"
    case flow = "Flow"
    case scripts = "Scripts"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .process: return "play.rectangle"
        case .flow: return "list.number"
        case .scripts: return "terminal"
        }
    }
}

struct ContentView: View {
    @State private var selection: Section? = .dashboard
    @EnvironmentObject var updates: UpdateChecker
    @State private var showDisclaimer = false

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                Button { showDisclaimer = true } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(Disclaimer.short).font(.caption).multilineTextAlignment(.leading)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Read the disclaimer")
                .overlay(alignment: .bottomTrailing) {
                    if let v = AppInfo.version {
                        Text("v\(v)").font(.caption2).foregroundStyle(.tertiary).padding(.trailing, 8).padding(.bottom, 2)
                    }
                }
            }
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .process: ProcessView()
            case .flow: FlowView()
            case .scripts: ScriptsView()
            }
        }
        .sheet(isPresented: $showDisclaimer) { DisclaimerSheet() }
        .task { await updates.checkOnLaunch() }
        .alert(
            updates.alert?.title ?? "",
            isPresented: Binding(get: { updates.alert != nil }, set: { if !$0 { updates.alert = nil } }),
            presenting: updates.alert
        ) { alert in
            if case .available(let release, _) = alert {
                Button("Download") { NSWorkspace.shared.open(release.htmlURL) }
                Button("Later", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
    }
}

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

func fileSize(_ url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
}
