import SwiftUI
import UniformTypeIdentifiers

struct ProcessView: View {
    @EnvironmentObject var scripts: ScriptStore
    @EnvironmentObject var flow: FlowStore
    @EnvironmentObject var runner: Runner

    @State private var inputs: [URL] = []
    @State private var targeted = false
    @State private var useRange = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var range: (start: String, end: String)? {
        useRange ? (Self.formatter.string(from: startDate), Self.formatter.string(from: endDate)) : nil
    }

    private var rangeInvalid: Bool { useRange && startDate > endDate }
    private var activeSteps: [FlowStep] { flow.steps.filter(\.enabled) }

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 380)
            Divider()
            ResultsView(inputsEmpty: inputs.isEmpty)
        }
        .navigationTitle("Process")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            dropZone
            fileList
            rangeSection
            flowSummary
            Spacer(minLength: 0)
            runButtons
        }
        .padding(16)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc").font(.system(size: 28))
            Text("Drop one or more files here").font(.headline)
            Text(".csv, .log, .txt… any text file").font(.caption).foregroundStyle(.secondary)
            Button("Choose files…", action: chooseFiles)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        } isTargeted: { targeted = $0 }
        .disabled(runner.isRunning)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Files (\(inputs.count))").font(.subheadline.bold())
                Spacer()
                if !inputs.isEmpty && !runner.isRunning {
                    Button("Remove all") { inputs.removeAll() }.buttonStyle(.link)
                }
            }
            if inputs.isEmpty {
                Text("None yet").font(.caption).foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(inputs, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text(formatBytes(fileSize(url))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { inputs.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .disabled(runner.isRunning)
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: 160)
            }
        }
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Date range (for steps using {start} / {end})", isOn: $useRange)
                .font(.subheadline)
            if useRange {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, displayedComponents: .date)
                Text("Both days are inclusive.").font(.caption).foregroundStyle(.secondary)
                if rangeInvalid {
                    Text("The start date must be on or before the end date.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .disabled(runner.isRunning)
    }

    private var flowSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Flow to run").font(.subheadline.bold())
            ForEach(Array(activeSteps.enumerated()), id: \.element.id) { i, step in
                let skipped = step.needsDateRange && !useRange
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(i + 1).").foregroundStyle(.secondary)
                    Text(step.script).font(.system(.caption, design: .monospaced))
                    if skipped {
                        Text("(skipped without a range)").font(.caption2).foregroundStyle(.orange)
                    }
                }
                .opacity(skipped ? 0.6 : 1)
            }
            if activeSteps.isEmpty {
                Text("No active steps. Edit them in “Flow”.").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var runButtons: some View {
        HStack {
            if runner.isRunning {
                Button(role: .destructive) { runner.cancel() } label: {
                    Label("Cancel", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else {
                Button {
                    runner.start(inputs: inputs, flow: flow.steps, scripts: scripts, range: range)
                } label: {
                    Label("Run flow", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(inputs.isEmpty || activeSteps.isEmpty || rangeInvalid)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose the files to process"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !inputs.contains(url) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                inputs.append(url)
            }
        }
    }
}

struct ResultsView: View {
    @EnvironmentObject var runner: Runner
    let inputsEmpty: Bool

    var body: some View {
        VStack(spacing: 0) {
            if runner.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(inputsEmpty ? "Add files and run the flow" : "Press “Run flow”")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("Results").font(.headline)
                    Spacer()
                    Button("Export report…", action: export).disabled(runner.isRunning)
                }
                .padding(12)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(runner.files) { file in FileCard(file: file) }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "report.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = ""
        for f in runner.files {
            text += "==== \(f.url.path)\n\n"
            for s in f.steps {
                text += "$ \(s.command.isEmpty ? s.script : s.command)\n\(s.output)\n\n"
            }
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct StatusIcon: View {
    let status: RunStatus
    var body: some View {
        switch status {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped: Image(systemName: "arrow.uturn.right.circle").foregroundStyle(.orange)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
        }
    }
}

struct FileCard: View {
    let file: FileRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusIcon(status: file.status)
                Text(file.url.lastPathComponent).font(.headline)
                Text(formatBytes(fileSize(file.url))).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(file.steps.enumerated()), id: \.element.id) { i, step in
                StepView(index: i + 1, step: step)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }
}

struct StepView: View {
    let index: Int
    let step: StepRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusIcon(status: step.status)
                Text("\(index). \(step.script)").font(.subheadline.bold())
                Spacer()
                if step.status == .running, let started = step.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        Text(elapsed(ctx.date.timeIntervalSince(started))).monospacedDigit()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else if let d = step.duration {
                    Text(elapsed(d)).font(.caption).foregroundStyle(.secondary)
                }
                if !step.output.isEmpty {
                    Button { copy(step.output) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).help("Copy output")
                }
            }
            if !step.command.isEmpty {
                Text("$ " + step.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !step.output.isEmpty {
                Text(step.output)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
        }
    }

    private func elapsed(_ t: TimeInterval) -> String {
        t < 60 ? String(format: "%.1f s", t) : String(format: "%d min %02d s", Int(t) / 60, Int(t) % 60)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
