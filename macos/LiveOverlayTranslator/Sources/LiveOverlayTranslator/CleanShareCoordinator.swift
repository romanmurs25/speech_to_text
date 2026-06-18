import AppKit
import Foundation
import SwiftUI

#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

@MainActor
final class CleanShareCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var diagnostics: [CleanShareDiagnosticWindow] = []
    private var window: NSWindow?

    func start() async throws {
        #if canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.current
        let ownPID = ProcessInfo.processInfo.processIdentifier
        diagnostics = content.windows.map {
            CleanShareDiagnosticWindow(
                windowID: UInt32($0.windowID),
                owningApplicationBundleID: $0.owningApplication?.bundleIdentifier ?? "unknown",
                isExcluded: $0.owningApplication?.processID == ownPID
            )
        }
        #endif

        let feedWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        feedWindow.title = "LiveOverlayTranslator - Clean Feed"
        feedWindow.contentView = NSHostingView(rootView: CleanFeedView(isRunning: true))
        feedWindow.orderFrontRegardless()
        window = feedWindow
        isRunning = true
    }

    func stop() {
        window?.orderOut(nil)
        window = nil
        isRunning = false
    }
}

struct CleanShareDiagnosticWindow: Identifiable, Equatable {
    let id = UUID()
    let windowID: UInt32
    let owningApplicationBundleID: String
    let isExcluded: Bool
}

struct CleanFeedView: View {
    let isRunning: Bool

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Text(isRunning ? "SAFE SHARE" : "Clean Feed stopped")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(isRunning ? .green : .secondary)
                Text("Share this Clean Feed window, not the physical Entire Screen source.")
                    .foregroundStyle(.white)
            }
        }
    }
}
