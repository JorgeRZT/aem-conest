import SwiftUI

/// Log files dropped by the user, shared by the Dashboard and the Content Requests section so
/// they only have to be added once.
@MainActor
final class SourceStore: ObservableObject {
    @Published var urls: [URL] = []

    func add(_ new: [URL]) {
        for url in new where url.isFileURL && !urls.contains(url) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                urls.append(url)
            }
        }
    }

    func remove(_ url: URL) { urls.removeAll { $0 == url } }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose the files to analyze"
        if panel.runModal() == .OK { add(panel.urls) }
    }
}

/// The list of dropped files with "Choose…" and remove buttons.
struct SourceFilesView: View {
    @EnvironmentObject var sources: SourceStore
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "arrow.down.doc")
                Text(sources.urls.isEmpty ? "Drop one or more files here" : "\(sources.urls.count) file(s)")
                    .font(.headline)
                Button("Choose…") { sources.choose() }.disabled(disabled)
                if !sources.urls.isEmpty {
                    Button("Remove all") { sources.urls.removeAll() }
                        .buttonStyle(.link).disabled(disabled)
                }
            }
            ForEach(sources.urls, id: \.self) { url in
                HStack(spacing: 6) {
                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Text(formatBytes(fileSize(url))).font(.caption).foregroundStyle(.secondary)
                    Button { sources.remove(url) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).disabled(disabled)
                }
            }
        }
    }
}

private struct FileDropTarget: ViewModifier {
    let sources: SourceStore
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                sources.add(urls)
                return true
            } isTargeted: { targeted = $0 }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(6).allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Accepts files dropped anywhere on the view and adds them to `sources`.
    func fileDropTarget(_ sources: SourceStore) -> some View { modifier(FileDropTarget(sources: sources)) }
}

/// Spinner, phase and elapsed time of a running analysis, plus its error and notes.
struct AnalysisStatusView: View {
    let isLoading: Bool
    let phase: String
    let phaseStart: Date?
    let error: String?
    let notes: [String]

    var body: some View {
        if isLoading, let started = phaseStart {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(phase)
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    let t = Int(ctx.date.timeIntervalSince(started))
                    Text(String(format: "%d:%02d", t / 60, t % 60)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                .textSelection(.enabled)
        }
        ForEach(notes, id: \.self) { n in
            Text(n).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
