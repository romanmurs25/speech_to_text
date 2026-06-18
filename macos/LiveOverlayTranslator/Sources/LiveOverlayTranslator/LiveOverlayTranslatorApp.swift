import AppKit
import LiveOverlayTranslatorCore
import SwiftUI

@main
struct LiveOverlayTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayState = OverlayState()
    private var overlayController: OverlayWindowController?
    private var shortcutController: GlobalShortcutController?
    private let cleanShareCoordinator = CleanShareCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = OverlayWindowController(state: overlayState)
        overlayController = controller
        controller.show()

        shortcutController = GlobalShortcutController(
            toggleOverlay: { [weak controller] in controller?.toggleVisibility() },
            emergencyHide: { [weak self] in
                self?.overlayController?.hide()
                self?.cleanShareCoordinator.stop()
            }
        )
        shortcutController?.install()

        Task {
            let source = MockOverlayEventSource()
            for await event in source.events() {
                overlayState.apply(event)
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Text("LiveOverlayTranslator")
            Text("Share the Clean Feed window, not the physical Entire Screen source.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
