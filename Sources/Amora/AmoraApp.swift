import AppKit
import Combine
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = ActivityState()
    private let settings = SettingsModel()
    private let petPreferences = PetPreferences()
    private let petModels = PetModelLibrary()
    private let agentApps = AgentApps()
    private let agenda = CalendarAgenda()
    private var receiver: ActivityReceiver?
    private var petPanels: [UUID: PetPanelController] = [:]
    private var companionPanels: [CompanionKey: CompanionPanelController] = [:]
    private var companionUpdates: AnyCancellable?
    private var staleSessionTimer: Timer?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var petsWindow: NSWindow?
    private var registrationWindow: NSWindow?
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
                apps: agentApps,
                agenda: agenda,
                openPets: { [weak self] in self?.showPets() },
                openSettings: { [weak self] in self?.showSettings() }
            )
        )
        petPreferences.onPetsChanged = { [weak self] in self?.syncPetPanels() }
        syncPetPanels()
        // Both publish before they change; hop to the next turn of the main queue to read the new values.
        companionUpdates = state.objectWillChange
            .merge(with: petPreferences.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncCompanionPanels() }
        staleSessionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.removeStaleSessions() }
        }
        settings.applyStoredLaunchAtLogin()
        agenda.startMonitoring()
        let receiver = ActivityReceiver { [weak self] event in
            guard let self else { return }
            self.state.record(event)
            self.statusItem?.button?.toolTip = activitySummary(self.state.rows)
        }
        self.receiver = receiver
        do {
            try receiver.start()
        } catch {
            state.error = "Could not start the activity receiver: \(error.localizedDescription)"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        staleSessionTimer?.invalidate()
        receiver?.stop()
        agenda.stopMonitoring()
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
        agenda.refresh()
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
        for panel in companionPanels.values {
            panel.setHostsMenu(false)
        }
        switch anchor {
        case .pet(let id):
            petPanels[id]?.setHostsMenu(true)
        case .companion(let pet, let session):
            companionPanels[CompanionKey(pet: pet, session: session)]?.setHostsMenu(true)
        case .statusItem:
            break
        }
    }

    private func syncPetPanels() {
        let ids = Set(petPreferences.pets.map(\.id))
        for (id, panel) in petPanels where !ids.contains(id) {
            panel.hide()
            petPanels[id] = nil
        }
        for pet in petPreferences.pets {
            let panel = petPanels[pet.id] ?? makePanel(id: pet.id)
            petPanels[pet.id] = panel
            if pet.isVisible, !panel.window.isVisible {
                panel.show()
            } else if !pet.isVisible, panel.window.isVisible {
                panel.hide()
            }
        }
    }

    /// Gives each open session after a pet's own a companion beside that pet, and lines the pack up.
    private func syncCompanionPanels() {
        var wanted: Set<CompanionKey> = []
        var packs: [(pet: UUID, window: NSWindow, sessions: [AgentActivity])] = []
        if petPreferences.petPerSession {
            for pet in petPreferences.pets where pet.isVisible {
                guard let window = petPanels[pet.id]?.window, window.isVisible else { continue }
                let sessions = companionSessions(scope: pet.scope, sessions: state.sessions)
                guard !sessions.isEmpty else { continue }
                packs.append((pet.id, window, sessions))
                wanted.formUnion(sessions.map { CompanionKey(pet: pet.id, session: $0.id) })
            }
        }
        for (key, panel) in companionPanels where !wanted.contains(key) {
            if menuAnchor == .companion(key.pet, key.session) {
                popover.performClose(nil)
            }
            panel.hide()
            companionPanels[key] = nil
        }
        for pack in packs {
            let scale = petPreferences.scale(for: pack.pet)
            let sizes = pack.sessions.map { session in
                PetMetrics.size(for: session.isSubagent ? scale * PetMetrics.subagentScale : scale)
            }
            let screen = pack.window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let frames = companionFrames(petFrame: pack.window.frame, sizes: sizes, screenFrame: screen)
            for (session, frame) in zip(pack.sessions, frames) {
                let key = CompanionKey(pet: pack.pet, session: session.id)
                let panel = companionPanels[key] ?? makeCompanionPanel(key, size: frame.size, pet: pack.window)
                companionPanels[key] = panel
                panel.setFrame(frame)
                if !panel.window.isVisible {
                    panel.show()
                }
            }
        }
    }

    private func makeCompanionPanel(_ key: CompanionKey, size: CGSize, pet: NSWindow) -> CompanionPanelController {
        CompanionPanelController(
            size: size,
            pet: pet,
            content: PetView(
                state: state,
                preferences: petPreferences,
                library: petModels,
                agenda: agenda,
                petID: key.pet,
                session: key.session
            ),
            onSelect: { [weak self] in
                guard let self, let panel = self.companionPanels[key] else { return }
                self.presentMenu(anchor: .companion(key.pet, key.session), view: panel.menuAnchorView, edge: .maxY)
            }
        )
    }

    private func makePanel(id: UUID) -> PetPanelController {
        PetPanelController(
            petID: id,
            preferences: petPreferences,
            content: PetView(state: state, preferences: petPreferences, library: petModels, agenda: agenda, petID: id),
            onSelect: { [weak self] in
                guard let self else { return }
                self.petPreferences.setActive(id)
                guard let panel = self.petPanels[id] else { return }
                self.presentMenu(anchor: .pet(id), view: panel.menuAnchorView, edge: .maxY)
            }
        )
    }

    private func addPet(modelID: String?, scope: PetScope) {
        let screen = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        petPreferences.addPet(modelID: modelID, scope: scope, windowSize: PetMetrics.size, screenFrame: screen)
    }

    private func showPets() {
        popover.performClose(nil)
        petModels.reload()
        let window = petsWindow ?? makeAutosizingWindow(
            title: "Pets",
            rootView: PetManagerView(
                preferences: petPreferences,
                library: petModels,
                addPet: { [weak self] modelID, scope in self?.addPet(modelID: modelID, scope: scope) },
                registerModel: { [weak self] in self?.showRegistration() }
            )
        )
        petsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showRegistration() {
        let window = registrationWindow ?? makeAutosizingWindow(
            title: "Register Pet Model",
            rootView: PetModelRegistrationView(
                library: petModels,
                onRegistered: { [weak self] _ in
                    self?.registrationWindow?.close()
                    self?.showPets()
                }
            )
        )
        registrationWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeAutosizingWindow(title: String, rootView: some View) -> NSWindow {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func showSettings() {
        popover.performClose(nil)
        settings.refresh()
        agenda.refresh()
        let window = settingsWindow ?? makeAutosizingWindow(
            title: "Settings",
            rootView: SettingsView(model: settings, agenda: agenda)
        )
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
        for panel in companionPanels.values {
            panel.setHostsMenu(false)
        }
    }
}

private struct CompanionKey: Hashable {
    let pet: UUID
    let session: String
}

private struct ActivityMenu: View {
    @ObservedObject var state: ActivityState
    @ObservedObject var apps: AgentApps
    @ObservedObject var agenda: CalendarAgenda
    let openPets: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amora").font(.headline)
            if let error = state.error {
                Text(error).foregroundStyle(.red)
            } else if !state.rows.isEmpty {
                ForEach(state.rows) { agent in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if agent.isSubagent {
                                Label(agent.subagentType ?? "Subagent", systemImage: "arrow.turn.down.right")
                                Text("Subagent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(agent.source.displayName)
                                if let project = agent.project {
                                    Text(project)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .padding(.leading, agent.isSubagent ? 12 : 0)
                        Spacer(minLength: 8)
                        Label(agent.activity.label, systemImage: agent.activity.symbolName)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("Waiting for activity").foregroundStyle(.secondary)
            }
            Divider()
            Text("Agenda").font(.headline)
            AgendaSection(agenda: agenda, openSettings: openSettings)
            Divider()
            Text("Apps").font(.headline)
            ForEach(apps.listings) { listing in
                AgentAppRow(apps: apps, listing: listing)
            }
            Divider()
            Button("Pets…", action: openPets)
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
