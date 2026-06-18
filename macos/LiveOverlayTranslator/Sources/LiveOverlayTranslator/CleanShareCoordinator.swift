import AppKit
import Foundation
import SwiftUI

@MainActor
final class CleanShareCoordinator: ObservableObject {
    enum CleanShareError: LocalizedError {
        case featureNotAvailable

        var errorDescription: String? {
            "Clean Share is not implemented in the P0 microphone build."
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var diagnostics: [CleanShareDiagnosticWindow] = []
    private var window: NSWindow?

    func start() async throws {
        isRunning = false
        throw CleanShareError.featureNotAvailable
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
                Text("Clean Feed unavailable")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Clean Share is not implemented in this P0 microphone build.")
                    .foregroundStyle(.white)
            }
        }
    }
}
