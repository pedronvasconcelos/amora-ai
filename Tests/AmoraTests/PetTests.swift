import AppKit
import Foundation
import Testing
@testable import Amora

@MainActor
@Test func petPreferencePersistsVisibilityAndOrigin() throws {
    let suite = "amora.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let preferences = PetPreferences(defaults: defaults)
    #expect(preferences.isVisible == true)
    #expect(preferences.origin == nil)

    preferences.setVisible(false)
    preferences.setOrigin(CGPoint(x: 12, y: 34))
    let restored = PetPreferences(defaults: defaults)
    #expect(restored.isVisible == false)
    #expect(restored.origin == CGPoint(x: 12, y: 34))

    restored.setVisible(true)
    #expect(restored.origin == CGPoint(x: 12, y: 34))
    #expect(PetPreferences(defaults: defaults).isVisible == true)
}

@Test func clampsPetOriginToTheVisibleScreen() {
    let screen = CGRect(x: 100, y: 200, width: 800, height: 600)
    let size = CGSize(width: 100, height: 120)

    #expect(clampedPetOrigin(CGPoint(x: 150, y: 250), windowSize: size, screenFrame: screen) == CGPoint(x: 150, y: 250))
    #expect(clampedPetOrigin(CGPoint(x: 0, y: 0), windowSize: size, screenFrame: screen) == CGPoint(x: 100, y: 200))
    #expect(clampedPetOrigin(CGPoint(x: 5_000, y: 5_000), windowSize: size, screenFrame: screen) == CGPoint(x: 800, y: 680))

    let huge = CGSize(width: 2_000, height: 2_000)
    #expect(clampedPetOrigin(CGPoint(x: 400, y: 400), windowSize: huge, screenFrame: screen) == CGPoint(x: 100, y: 200))
    #expect(defaultPetOrigin(windowSize: size, screenFrame: screen) == CGPoint(x: 772, y: 228))
}

@Test func mapsActivityToPetPose() {
    #expect(petPose(for: nil) == .resting)
    #expect(petPose(for: .thinking) == .thinking)
    #expect(petPose(for: .working) == .working)
    #expect(petPose(for: .waiting) == .waiting)
    #expect(petPose(for: .finished) == .finished)
    let event = ActivityEvent.decode(Data(#"{"v":1,"source":"cursor","activity":"thinking"}"#.utf8))
    #expect(petAccessibilityLabel(for: event) == "Cursor, thinking")
    #expect(petAccessibilityLabel(for: nil) == "Amora, resting")
}

@MainActor
@Test func petPanelStaysFloatingWithoutTakingFocus() throws {
    let suite = "amora.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = PetPreferences(defaults: defaults)
    preferences.setOrigin(CGPoint(x: -500, y: -500))
    let panel = PetPanelController(preferences: preferences, content: PetView(state: ActivityState()))
    let window = panel.window

    #expect(window.styleMask.contains(.borderless))
    #expect(window.styleMask.contains(.nonactivatingPanel))
    #expect(window.level == .floating)
    #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(window.collectionBehavior.contains(.stationary))
    #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(window.collectionBehavior.contains(.ignoresCycle))
    #expect(window.hidesOnDeactivate == false)
    #expect(window.isOpaque == false)
    #expect(window.canBecomeKey == false)
    #expect(window.canBecomeMain == false)

    let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    panel.place(on: screen)
    let placed = clampedPetOrigin(
        CGPoint(x: -500, y: -500),
        windowSize: window.frame.size,
        screenFrame: screen
    )
    #expect(window.frame.origin.x == placed.x)
    #expect(window.frame.origin.y == placed.y)
    #expect(preferences.origin == CGPoint(x: -500, y: -500))
}
