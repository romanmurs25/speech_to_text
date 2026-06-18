import AppKit
import LiveOverlayTranslatorCore
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: NSPanel

    init(state: OverlayState) {
        panel = NSPanel(
            contentRect: NSRect(x: 80, y: 500, width: 560, height: 460),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "LiveOverlayTranslator"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggleVisibility() {
        panel.isVisible ? hide() : show()
    }

    func setClickThrough(_ isClickThrough: Bool) {
        panel.ignoresMouseEvents = isClickThrough
    }

    func setOpacity(_ opacity: Double) {
        panel.alphaValue = max(0.2, min(1.0, opacity))
    }
}

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LiveOverlayTranslator")
                    .font(.headline)
                Spacer()
                statusText
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !state.provisionalText.isEmpty {
                Text(state.provisionalText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.cards) { card in
                        OverlayCardView(card: card, isPending: state.pendingTranslationIDs.contains(card.clientUtteranceID))
                    }
                }
            }

            if let error = state.recoverableError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
        .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: some View {
        switch state.connectionStatus {
        case .disconnected:
            Text("Idle")
        case .connected:
            Text("Connected")
        case let .degraded(reason):
            Text("Recovering: \(reason)")
        case .closed:
            Text("Closed")
        case let .failed(code):
            Text("Failed: \(code)")
        }
    }
}

struct OverlayCardView: View {
    let card: OverlayCard
    let isPending: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.speaker == .local ? "Local" : "Remote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isPending {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text(card.originalTranscript)
                .font(.body)

            if let result = card.result {
                labeled("RU", result.translationRU)
                labeled("EN", result.translationEN)
                if result.replyNeeded {
                    Divider()
                    labeled("Reply RU", result.suggestedReplyRU)
                    labeled("Reply EN", result.suggestedReplyEN)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
    }
}
