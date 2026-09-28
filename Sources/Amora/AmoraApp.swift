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
    private let agentApps = AgentApps()
    private var receiver: ActivityReceiver?
    private var petPanels: [UUID: PetPanelController] = [:]
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let popover = NSPopover()
    private var menuAnchor: MenuAnchor?
    private var closedAnchor: MenuAnchor?
    private var closedAt: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Amora")
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ActivityMenu(
                state: state,
                preferences: petPreferences,
                apps: agentApps,
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
        presentMenu(anchor: .statusItem, view: button, edge: .minY)
    }

    private func presentMenu(anchor: MenuAnchor, view: NSView, edge: NSRectEdge) {
        if closedAnchor == anchor, ProcessInfo.processInfo.systemUptime - closedAt < 0.3 {
            closedAnchor = nil
            return
        }
        closedAnchor = nil
        agentApps.refresh()
        switch menuToggle(isShown: popover.isShown, current: menuAnchor, requested: anchor) {
        case .close:
            popover.performClose(nil)
        case .show:
            if case .pet = anchor {
                NSApp.activate(ignoringOtherApps: true)
            }
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
            menuAnchor = anchor
            applyMenuHost(anchor)
        }
    }

    private func applyMenuHost(_ anchor: MenuAnchor) {
        for panel in petPanels.values {
            panel.setHostsMenu(false)
        }
        if case .pet(let id) = anchor, let panel = petPanels[id] {
            panel.setHostsMenu(true)
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
                guard let self else { return }
                self.petPreferences.setActive(id)
                guard let panel = self.petPanels[id] else { return }
                self.presentMenu(anchor: .pet(id), view: panel.menuAnchorView, edge: .maxY)
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

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        closedAnchor = menuAnchor
        closedAt = ProcessInfo.processInfo.systemUptime
        menuAnchor = nil
        for panel in petPanels.values {
            panel.setHostsMenu(false)
        }
    }
}

private struct ActivityMenu: View {
    @ObservedObject var state: ActivityState
    @ObservedObject var preferences: PetPreferences
    @ObservedObject var apps: AgentApps
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
            Text("Apps").font(.headline)
            ForEach(apps.listings) { listing in
                AgentAppRow(apps: apps, listing: listing)
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
        .frame(width: 300, alignment: .leading)
    }
}

private struct AgentAppRow: View {
    @ObservedObject var apps: AgentApps
    let listing: AgentAppListing

    var body: some View {
        HStack(spacing: 8) {
            Button {
                apps.open(listing.kind)
            } label: {
                HStack(spacing: 8) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.name)
                        Text(listing.state.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            .disabled(listing.state == .notInstalled)
            .accessibilityLabel("Open \(listing.name)")
            if listing.state == .running {
                Button("Close") {
                    apps.close(listing.kind)
                }
                .accessibilityLabel("Close \(listing.name)")
            }
        }
    }

    private var icon: NSImage {
        apps.icon(for: listing.kind)
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: listing.name)
            ?? NSImage()
    }
}
