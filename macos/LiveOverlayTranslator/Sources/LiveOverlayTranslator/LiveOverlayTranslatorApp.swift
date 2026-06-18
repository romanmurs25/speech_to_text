import AppKit
import LiveOverlayTranslatorCore
import SwiftUI

@main
struct LiveOverlayTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("LiveOverlayTranslator", id: "controls") {
            ControlPanelView(controller: appDelegate.controller)
        }

        Settings {
            ControlPanelView(controller: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = ApplicationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.applicationDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await controller.shutdown()
        }
    }
}

struct ControlPanelView: View {
    @ObservedObject var controller: ApplicationController

    private var controlsLocked: Bool {
        controller.runState == .connecting ||
            controller.runState == .listening ||
            controller.runState == .stopping
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LiveOverlayTranslator")
                .font(.title3.weight(.semibold))

            Picker("Mode", selection: $controller.mode) {
                ForEach(ApplicationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsLocked)

            VStack(alignment: .leading, spacing: 6) {
                Text("Backend WebSocket URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("ws://127.0.0.1:8787/ws", text: $controller.backendURLString)
                    .textFieldStyle(.roundedBorder)
                    .disabled(controller.mode == .localMock || controlsLocked)
            }

            HStack {
                Label("P0 source: Microphone", systemImage: "mic")
                Spacer()
                Text(controller.microphoneState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start Listening") {
                    Task {
                        await controller.startListening()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(controlsLocked)

                Button("Stop Listening") {
                    Task {
                        await controller.stopListening()
                    }
                }
                .disabled(controller.runState == .idle || controller.runState == .stopping)

                Spacer()

                Text(controller.runState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("System audio is unavailable in this P0 build.")
                Text("Clean Share is not implemented; sharing Entire Screen can expose the overlay.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
