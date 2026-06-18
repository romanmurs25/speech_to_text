import AppKit
import Foundation

@MainActor
final class GlobalShortcutController {
    private let toggleOverlay: () -> Void
    private let emergencyHide: () -> Void
    private var monitor: Any?

    init(toggleOverlay: @escaping () -> Void, emergencyHide: @escaping () -> Void) {
        self.toggleOverlay = toggleOverlay
        self.emergencyHide = emergencyHide
    }

    func install() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.control, .option]) else { return }
            if event.charactersIgnoringModifiers == "o" {
                Task { @MainActor in self?.toggleOverlay() }
            }
            if event.charactersIgnoringModifiers == "h" {
                Task { @MainActor in self?.emergencyHide() }
            }
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
