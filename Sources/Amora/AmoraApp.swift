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
    private let settings = SettingsModel()
    private let petPreferences = PetPreferences()
    private var receiver: ActivityReceiver?
    private var petPanel: PetPanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Amora")
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        statusItem = item
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ActivityMenu(
                state: state,
                preferences: petPreferences,
                openSettings: { [weak self] in self?.showSettings() },
                setPetVisible: { [weak self] visible in self?.setPetVisible(visible) }
            )
        )
        let panel = PetPanelController(preferences: petPreferences, content: PetView(state: state))
        petPanel = panel
        if petPreferences.isVisible {
            panel.show()
        }
        settings.applyStoredLaunchAtLogin()
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

    private func setPetVisible(_ visible: Bool) {
        petPreferences.setVisible(visible)
        if visible {
            petPanel?.show()
        } else {
            petPanel?.hide()
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        settings.refresh()
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeSettingsWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: settings))
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        controller.view.frame = NSRect(x: 0, y: 0, width: 420, height: 1)
        controller.view.layoutSubtreeIfNeeded()
        var size = controller.view.fittingSize
        size.width = 420
        if size.height < 300 || size.height > 640 { size.height = 420 }
        window.setContentSize(size)
        window.center()
        return window
    }
}

private struct ActivityMenu: View {
    @ObservedObject var state: ActivityState
    @ObservedObject var preferences: PetPreferences
    let openSettings: () -> Void
    let setPetVisible: (Bool) -> Void

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
            Button(preferences.isVisible ? "Hide pet" : "Show pet") {
                setPetVisible(!preferences.isVisible)
            }
            Button("Settings…", action: openSettings)
            Divider()
            Button("Quit Amora") { NSApplication.shared.terminate(nil) }
        }
        .padding(16)
        .frame(width: 240, alignment: .leading)
    }
}
