import SwiftUI

@main
struct AEMConestApp: App {
    @StateObject private var scripts = ScriptStore()
    @StateObject private var flow = FlowStore()
    @StateObject private var runner = Runner()
    @StateObject private var dashboard = DashboardModel()

    var body: some Scene {
        WindowGroup("AEM Conest") {
            ContentView()
                .environmentObject(scripts)
                .environmentObject(flow)
                .environmentObject(runner)
                .environmentObject(dashboard)
                .frame(minWidth: 960, minHeight: 600)
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

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .process: ProcessView()
            case .flow: FlowView()
            case .scripts: ScriptsView()
            }
        }
    }
}

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

func fileSize(_ url: URL) -> Int64 {
    Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
}
