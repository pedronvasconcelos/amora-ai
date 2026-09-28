import AppKit
import Foundation
import Testing
@testable import Amora

@MainActor
@Test func freshPetStoreStartsWithOneVisiblePet() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults

    let preferences = PetPreferences(defaults: defaults)
    #expect(preferences.pets.count == 1)
    #expect(preferences.pets[0].isVisible == true)
    #expect(preferences.pets[0].origin == nil)
    #expect(preferences.activePetID == preferences.pets[0].id)
    #expect(preferences.canAddPet == true)

    let id = preferences.pets[0].id
    preferences.setVisible(false, for: id)
    preferences.setOrigin(CGPoint(x: 12, y: 34), for: id)
    let restored = PetPreferences(defaults: defaults)
    #expect(restored.pets.count == 1)
    #expect(restored.pets[0].id == id)
    #expect(restored.pets[0].isVisible == false)
    #expect(restored.pets[0].origin == CGPoint(x: 12, y: 34))
    #expect(restored.activePetID == id)

    restored.setVisible(true, for: id)
    #expect(restored.pets[0].origin == CGPoint(x: 12, y: 34))
    #expect(PetPreferences(defaults: defaults).pets[0].isVisible == true)
}

@MainActor
@Test func migratesLegacyPetVisibilityAndOrigin() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    defaults.set(false, forKey: PetPreferences.visibleKey)
    defaults.set(12.0, forKey: PetPreferences.originXKey)
    defaults.set(34.0, forKey: PetPreferences.originYKey)

    let preferences = PetPreferences(defaults: defaults)
    #expect(preferences.pets.count == 1)
    #expect(preferences.pets[0].isVisible == false)
    #expect(preferences.pets[0].origin == CGPoint(x: 12, y: 34))
    let id = preferences.pets[0].id

    defaults.set(true, forKey: PetPreferences.visibleKey)
    defaults.set(99.0, forKey: PetPreferences.originXKey)
    let restored = PetPreferences(defaults: defaults)
    #expect(restored.pets[0].id == id)
    #expect(restored.pets[0].isVisible == false)
    #expect(restored.pets[0].origin == CGPoint(x: 12, y: 34))
    #expect(restored.activePetID == id)
}

@MainActor
@Test func addPetOffsetsTheNewPetAndLeavesTheOthersAlone() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    let preferences = PetPreferences(defaults: defaults)
    let first = preferences.pets[0].id
    let screen = CGRect(x: 100, y: 200, width: 800, height: 600)
    let size = CGSize(width: 100, height: 120)
    preferences.setOrigin(CGPoint(x: 150, y: 250), for: first)

    preferences.addPet(windowSize: size, screenFrame: screen)
    #expect(preferences.pets.count == 2)
    #expect(preferences.activePetID == preferences.pets[1].id)
    #expect(preferences.pets[1].isVisible == true)
    #expect(preferences.pets[1].origin == CGPoint(x: 114, y: 286))
    #expect(preferences.pets[0].isVisible == true)
    #expect(preferences.pets[0].origin == CGPoint(x: 150, y: 250))

    preferences.setVisible(false, for: preferences.pets[1].id)
    #expect(preferences.pets[0].isVisible == true)
    #expect(preferences.pets[1].isVisible == false)

    preferences.setActive(first)
    #expect(preferences.activePetID == first)
    preferences.setActive(UUID())
    #expect(preferences.activePetID == first)

    let restored = PetPreferences(defaults: defaults)
    #expect(restored.pets.map(\.id) == preferences.pets.map(\.id))
    #expect(restored.activePetID == first)
    #expect(restored.pets[1].isVisible == false)
    #expect(restored.pets[1].origin == CGPoint(x: 114, y: 286))
}

@MainActor
@Test func addPetStopsAtSix() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    let preferences = PetPreferences(defaults: defaults)
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let size = PetMetrics.size
    for _ in 0..<8 {
        preferences.addPet(windowSize: size, screenFrame: screen)
    }
    #expect(preferences.pets.count == PetPreferences.maximumPets)
    #expect(preferences.canAddPet == false)
    #expect(preferences.activePetID == preferences.pets[5].id)
}

@MainActor
@Test func petsKeepTheirModelAndCanBeRemoved() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    let preferences = PetPreferences(defaults: defaults)
    let counter = ChangeCounter()
    preferences.onPetsChanged = { counter.count += 1 }
    let first = preferences.pets[0].id
    #expect(preferences.canRemovePet == false)
    preferences.removePet(first)
    #expect(preferences.pets.map(\.id) == [first])

    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    preferences.addPet(modelID: "codie", windowSize: PetMetrics.size, screenFrame: screen)
    preferences.addPet(windowSize: PetMetrics.size, screenFrame: screen)
    let second = preferences.pets[1].id
    let third = preferences.pets[2].id
    #expect(preferences.pets[1].modelID == "codie")
    #expect(preferences.pets[2].modelID == nil)
    #expect(counter.count == 2)

    preferences.setModel("codie", for: first)
    preferences.setVisible(false, for: third)
    #expect(counter.count == 3)
    let restored = PetPreferences(defaults: defaults)
    #expect(restored.pets.map(\.modelID) == ["codie", "codie", nil])

    preferences.clearModel("codie")
    #expect(preferences.pets.map(\.modelID) == [nil, nil, nil])

    preferences.setActive(second)
    preferences.removePet(second)
    #expect(preferences.pets.map(\.id) == [first, third])
    #expect(preferences.activePetID == third)
    #expect(counter.count == 4)
    #expect(PetPreferences(defaults: defaults).pets.map(\.id) == [first, third])
}

@MainActor
@Test func decodesPetsSavedBeforeModelsExisted() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    let id = UUID()
    let legacy = #"[{"id":"\#(id.uuidString)","originX":10,"originY":20,"isVisible":true}]"#
    defaults.set(Data(legacy.utf8), forKey: PetPreferences.petsKey)

    let preferences = PetPreferences(defaults: defaults)
    #expect(preferences.pets.map(\.id) == [id])
    #expect(preferences.pets[0].modelID == nil)
    #expect(preferences.pets[0].origin == CGPoint(x: 10, y: 20))
}

@Test func placesTheNextPetAwayFromThePreviousOne() {
    let screen = CGRect(x: 100, y: 200, width: 800, height: 600)
    let size = CGSize(width: 100, height: 120)

    #expect(nextPetOrigin(after: nil, windowSize: size, screenFrame: screen) == CGPoint(x: 736, y: 264))
    #expect(nextPetOrigin(after: CGPoint(x: 150, y: 250), windowSize: size, screenFrame: screen) == CGPoint(x: 114, y: 286))
    #expect(nextPetOrigin(after: CGPoint(x: 100, y: 200), windowSize: size, screenFrame: screen) == CGPoint(x: 100, y: 236))
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
    #expect(petAccessibilityLabel(for: nil, isActive: true) == "Amora, resting, active")
}

@MainActor
@Test func petPanelStaysFloatingWithoutTakingFocus() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    let preferences = PetPreferences(defaults: defaults)
    let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    let size = CGSize(width: 100, height: 120)
    preferences.addPet(windowSize: size, screenFrame: screen)
    let first = preferences.pets[0].id
    let second = preferences.pets[1].id
    preferences.setOrigin(CGPoint(x: 40, y: 50), for: first)
    preferences.setOrigin(CGPoint(x: -500, y: -500), for: second)
    let panel = PetPanelController(
        petID: second,
        preferences: preferences,
        content: PetView(
            state: ActivityState(),
            preferences: preferences,
            library: PetModelLibrary(
                directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                codexDirectory: nil
            ),
            petID: second
        )
    )
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
    panel.setHostsMenu(true)
    #expect(window.canBecomeKey == true)
    panel.setHostsMenu(false)
    #expect(window.canBecomeKey == false)

    panel.place(on: screen)
    let placed = clampedPetOrigin(
        CGPoint(x: -500, y: -500),
        windowSize: window.frame.size,
        screenFrame: screen
    )
    #expect(window.frame.origin.x == placed.x)
    #expect(window.frame.origin.y == placed.y)
    #expect(preferences.origin(for: second) == CGPoint(x: -500, y: -500))
    #expect(preferences.origin(for: first) == CGPoint(x: 40, y: 50))
}

@MainActor
private final class ChangeCounter {
    var count = 0
}

private struct TemporaryDefaults {
    let name: String
    let defaults: UserDefaults

    func close() {
        defaults.removePersistentDomain(forName: name)
    }
}

private func temporaryDefaults() throws -> TemporaryDefaults {
    let name = "amora.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    return TemporaryDefaults(name: name, defaults: defaults)
}
