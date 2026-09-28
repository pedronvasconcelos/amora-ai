import AppKit
import SwiftUI

@MainActor
@main
struct AmoraApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class ActivityState: ObservableObject {
    @Published var event: ActivityEvent?
    @Published var error: String?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = ActivityState()
    private var receiver: ActivityReceiver?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Amora")
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        statusItem = item
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ActivityMenu(state: state))
        let receiver = ActivityReceiver { [weak self] event in
            self?.state.event = event
            self?.statusItem?.button?.toolTip = event.activity.rawValue.capitalized
        }
        self.receiver = receiver
        do {
            try receiver.start()
        } catch {
            state.error = "Could not start the activity receiver: \(error.localizedDescription)"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        receiver?.stop()
    }

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

private struct ActivityMenu: View {
    @ObservedObject var state: ActivityState
    @State private var hookMessage: String?
    private let codexHooks = CodexHooks()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amora").font(.headline)
            if let error = state.error {
                Text(error).foregroundStyle(.red)
            } else if let event = state.event {
                Text(event.activity.rawValue.capitalized)
                Text(event.source.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Waiting for activity").foregroundStyle(.secondary)
            }
            Divider()
            Button("Install Codex Hooks") {
                do {
                    try codexHooks.install()
                    hookMessage = "Installed. Review and trust Amora's hooks in Codex Hooks settings or /hooks in the CLI."
                } catch {
                    hookMessage = error.localizedDescription
                }
            }
            Button("Remove Codex Hooks") {
                do {
                    try codexHooks.remove()
                    hookMessage = "Amora's Codex hooks were removed."
                } catch {
                    hookMessage = error.localizedDescription
                }
            }
            if let hookMessage {
                Text(hookMessage).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button("Quit Amora") { NSApplication.shared.terminate(nil) }
        }
        .padding(16)
        .frame(width: 240, alignment: .leading)
    }
}
