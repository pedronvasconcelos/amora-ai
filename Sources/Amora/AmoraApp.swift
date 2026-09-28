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
    private var petPanels: [UUID: PetPanelController] = [:]
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
                setPetVisible: { [weak self] visible in self?.setPetVisible(visible) },
                addPet: { [weak self] in self?.addPet() },
                choosePet: { [weak self] id in self?.petPreferences.setActive(id) }
            )
        )
        installPetPanels()
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

    private func installPetPanels() {
        for pet in petPreferences.pets where petPanels[pet.id] == nil {
            let panel = makePanel(id: pet.id)
            petPanels[pet.id] = panel
            if pet.isVisible {
                panel.show()
            }
        }
    }

    private func makePanel(id: UUID) -> PetPanelController {
        PetPanelController(
            petID: id,
            preferences: petPreferences,
            content: PetView(state: state, preferences: petPreferences, petID: id),
            onSelect: { [weak self] in
                self?.petPreferences.setActive(id)
            }
        )
    }

    private func setPetVisible(_ visible: Bool) {
        let id = petPreferences.activePetID
        petPreferences.setVisible(visible, for: id)
        guard let panel = petPanels[id] else { return }
        if visible {
            panel.show()
        } else {
            panel.hide()
        }
    }

    private func addPet() {
        let screen = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let existing = Set(petPreferences.pets.map(\.id))
        petPreferences.addPet(windowSize: PetMetrics.size, screenFrame: screen)
        guard let pet = petPreferences.pets.last, !existing.contains(pet.id) else { return }
        let panel = makePanel(id: pet.id)
        petPanels[pet.id] = panel
        panel.show()
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
    let addPet: () -> Void
    let choosePet: (UUID) -> Void

    private var activePetIsVisible: Bool {
        preferences.activePet?.isVisible ?? false
    }

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
            Button(activePetIsVisible ? "Hide pet" : "Show pet") {
                setPetVisible(!activePetIsVisible)
            }
            Button("Add pet", action: addPet)
                .disabled(!preferences.canAddPet)
            Menu("Choose pet") {
                ForEach(Array(preferences.pets.enumerated()), id: \.element.id) { index, pet in
                    Button {
                        choosePet(pet.id)
                    } label: {
                        if pet.id == preferences.activePetID {
                            Label("Pet \(index + 1)", systemImage: "checkmark")
                        } else {
                            Text("Pet \(index + 1)")
                        }
                    }
                }
            }
            Button("Settings…", action: openSettings)
            Divider()
            Button("Quit Amora") { NSApplication.shared.terminate(nil) }
        }
        .padding(16)
        .frame(width: 240, alignment: .leading)
    }
}
