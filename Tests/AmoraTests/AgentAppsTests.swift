import Foundation
import Testing
@testable import Amora

@Test func agentAppStateReflectsInstalledAndRunning() {
    #expect(agentAppState(installed: false, running: false) == .notInstalled)
    #expect(agentAppState(installed: true, running: false) == .notRunning)
    #expect(agentAppState(installed: true, running: true) == .running)
    #expect(agentAppState(installed: false, running: true) == .running)
}

@Test func agentAppListingsStayInMenuOrder() {
    let listings = agentAppListings(
        installed: [AgentAppKind.cursor.bundleIdentifier],
        running: [AgentAppKind.claude.bundleIdentifier]
    )
    #expect(listings.map(\.kind) == [.cursor, .claude, .codex])
    #expect(listings.map(\.name) == ["Cursor", "Claude", "Codex"])
    #expect(listings.map(\.state) == [.notRunning, .running, .notInstalled])
    #expect(listings.map(\.state.label) == ["Not running", "Running", "Not installed"])
    #expect(AgentAppKind.cursor.bundleIdentifier == "com.todesktop.230313mzl4w4u92")
    #expect(AgentAppKind.claude.bundleIdentifier == "com.anthropic.claudefordesktop")
    #expect(AgentAppKind.codex.bundleIdentifier == "com.openai.codex")
}

@MainActor
@Test func agentAppsOpenAndCloseFollowState() {
    var opened: [String] = []
    var closed: [String] = []
    let lookup = AgentAppLookup(
        installed: { [AgentAppKind.cursor.bundleIdentifier, AgentAppKind.claude.bundleIdentifier] },
        running: { [AgentAppKind.claude.bundleIdentifier] },
        icon: { _ in nil },
        open: { opened.append($0) },
        close: { closed.append($0) }
    )
    let apps = AgentApps(lookup: lookup)

    apps.open(.codex)
    apps.close(.codex)
    apps.close(.cursor)
    apps.open(.cursor)
    apps.close(.claude)
    apps.open(.claude)

    #expect(opened == [AgentAppKind.cursor.bundleIdentifier, AgentAppKind.claude.bundleIdentifier])
    #expect(closed == [AgentAppKind.claude.bundleIdentifier])
}

@Test func menuToggleClosesOnlyTheSameAnchor() {
    let pet = UUID()
    #expect(menuToggle(isShown: false, current: nil, requested: .statusItem) == .show(.statusItem))
    #expect(menuToggle(isShown: true, current: .statusItem, requested: .statusItem) == .close)
    #expect(menuToggle(isShown: true, current: .statusItem, requested: .pet(pet)) == .show(.pet(pet)))
    #expect(menuToggle(isShown: true, current: .pet(pet), requested: .pet(pet)) == .close)
    #expect(menuToggle(isShown: true, current: .pet(pet), requested: .statusItem) == .show(.statusItem))
}
