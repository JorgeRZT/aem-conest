import SwiftUI

struct FlowView: View {
    @EnvironmentObject var scripts: ScriptStore
    @EnvironmentObject var flow: FlowStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps run in order, for each file. Drag to reorder.")
                .foregroundStyle(.secondary)

            List {
                ForEach($flow.steps) { $step in
                    StepRow(step: $step, index: (flow.steps.firstIndex { $0.id == step.id } ?? 0) + 1) {
                        flow.steps.removeAll { $0.id == step.id }
                    }
                }
                .onMove { flow.steps.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 200)

            HStack {
                Button {
                    flow.steps.append(FlowStep(script: scripts.names.first ?? "", args: "{cleaned}"))
                } label: { Label("Add step", systemImage: "plus") }
                Button("Restore default flow") { flow.resetToDefault() }
                Spacer()
            }

            GroupBox("Variables available in arguments") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(FlowVariable.docs, id: \.name) { v in
                        HStack(alignment: .firstTextBaseline) {
                            Text(v.name).font(.system(.caption, design: .monospaced)).frame(width: 90, alignment: .leading)
                            Text(v.text).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Arguments are separated by spaces; each one is passed to the script as a separate argument, so paths with spaces work. A step that uses {start}/{end} is skipped if no date range is enabled.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
        .padding(16)
        .navigationTitle("Flow")
    }
}

struct StepRow: View {
    @EnvironmentObject var scripts: ScriptStore
    @Binding var step: FlowStep
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            Toggle("", isOn: $step.enabled).labelsHidden()
            Text("\(index).").foregroundStyle(.secondary).frame(width: 22)
            Picker("", selection: $step.script) {
                if !scripts.names.contains(step.script) { Text("\(step.script) (not found)").tag(step.script) }
                ForEach(scripts.names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 220)
            TextField("arguments", text: $step.args)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            if !scripts.exists(step.script) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Script not found")
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
        }
        .opacity(step.enabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}
