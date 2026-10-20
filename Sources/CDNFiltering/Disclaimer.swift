import SwiftUI
import AppKit

enum Disclaimer {
    static let short = "Approximate figures only. Unofficial tool, not an Adobe guarantee."

    static let paragraphs = [
        "AEM Conest is an independent, unofficial tool. It is not an Adobe product and is not endorsed, supported or guaranteed by Adobe, even though its developer is an Adobe employee.",
        "It is not a 100% guarantee of anything. It can help you approximate a real figure, but its results must not be considered accurate or authoritative.",
        "Results are request counts computed with text filters over the log files you provide. They are not unique visitors or sessions, and the filters may include or exclude traffic incorrectly (for example, they do not remove all bots or automated traffic).",
        "Do not use these figures as a billing, contractual or usage-entitlement metric. For official numbers, use Adobe's own reporting and support channels.",
        "The software is provided \"as is\", without warranty of any kind (see the MIT License).",
    ]

    static var text: String { paragraphs.joined(separator: "\n\n") }
}

struct DisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Disclaimer", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            ForEach(Disclaimer.paragraphs, id: \.self) { Text($0) }
            HStack {
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

/// Standard About panel with the disclaimer in its credits.
@MainActor
func showAboutPanel() {
    let credits = NSAttributedString(
        string: "Disclaimer\n\n" + Disclaimer.text,
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
    )
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}
