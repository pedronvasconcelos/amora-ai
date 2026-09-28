import AppKit
import Foundation
import SwiftUI
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
    #expect(petAccessibilityLabel(for: [AgentActivity(source: .cursor, activity: .thinking)]) == "Cursor, thinking")
    #expect(petAccessibilityLabel(for: [
        AgentActivity(source: .cursor, activity: .thinking, project: "amora-ai")
    ]) == "Cursor, thinking, amora-ai")
    #expect(petAccessibilityLabel(for: [
        AgentActivity(source: .cursor, activity: .thinking),
        AgentActivity(source: .codex, activity: .waiting)
    ], isActive: true) == "Cursor, thinking; Codex, waiting, active")
    #expect(petAccessibilityLabel(for: []) == "Amora, resting")
    #expect(petAccessibilityLabel(for: [], isActive: true) == "Amora, resting, active")
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

@Test func resizeEdgesKeepTheOppositeSideAndThePetProportion() {
    let initial = CGRect(x: 100, y: 200, width: 104, height: 128)
    let screen = CGRect(x: 0, y: 0, width: 2_000, height: 1_600)
    let aspect = initial.width / initial.height

    let right = resizedPetFrame(
        initialFrame: initial,
        edge: .right,
        initialMouse: CGPoint(x: initial.maxX, y: initial.midY),
        mouse: CGPoint(x: initial.maxX + 52, y: initial.midY),
        screenFrame: screen
    )
    #expect(abs(right.minX - initial.minX) < 0.01)
    #expect(abs(right.midY - initial.midY) < 0.01)
    #expect(abs(right.width - 156) < 0.01)
    #expect(abs(right.width / right.height - aspect) < 0.001)

    let top = resizedPetFrame(
        initialFrame: initial,
        edge: .top,
        initialMouse: CGPoint(x: initial.midX, y: initial.maxY),
        mouse: CGPoint(x: initial.midX, y: initial.maxY + 64),
        screenFrame: screen
    )
    #expect(abs(top.minY - initial.minY) < 0.01)
    #expect(abs(top.midX - initial.midX) < 0.01)
    #expect(abs(top.height - 192) < 0.01)

    let corner = resizedPetFrame(
        initialFrame: initial,
        edge: .bottomLeft,
        initialMouse: CGPoint(x: initial.minX, y: initial.minY),
        mouse: CGPoint(x: initial.minX - 52, y: initial.minY - 64),
        screenFrame: screen
    )
    #expect(abs(corner.maxX - initial.maxX) < 0.01)
    #expect(abs(corner.maxY - initial.maxY) < 0.01)
    #expect(abs(corner.width - 156) < 0.01)
}

@Test func resizeClampsToTheCodexSizeRangeAndTheScreen() {
    let initial = CGRect(x: 100, y: 200, width: PetMetrics.size.width, height: PetMetrics.size.height)
    let huge = CGRect(x: 0, y: 0, width: 4_000, height: 3_000)
    let grown = resizedPetFrame(
        initialFrame: initial,
        edge: .right,
        initialMouse: CGPoint(x: initial.maxX, y: initial.midY),
        mouse: CGPoint(x: initial.maxX + 2_000, y: initial.midY),
        screenFrame: huge
    )
    let shrunk = resizedPetFrame(
        initialFrame: initial,
        edge: .right,
        initialMouse: CGPoint(x: initial.maxX, y: initial.midY),
        mouse: CGPoint(x: initial.minX, y: initial.midY),
        screenFrame: huge
    )
    #expect(abs(grown.width - PetMetrics.size.width * PetMetrics.maximumScale) < 0.01)
    #expect(abs(shrunk.width - PetMetrics.size.width * PetMetrics.minimumScale) < 0.01)
    #expect(abs(grown.width / grown.height - PetMetrics.size.width / PetMetrics.size.height) < 0.001)

    let screen = CGRect(x: 0, y: 0, width: 400, height: 400)
    let nearEdge = CGRect(x: 250, y: 100, width: PetMetrics.size.width, height: PetMetrics.size.height)
    let limited = resizedPetFrame(
        initialFrame: nearEdge,
        edge: .right,
        initialMouse: CGPoint(x: nearEdge.maxX, y: nearEdge.midY),
        mouse: CGPoint(x: nearEdge.maxX + 500, y: nearEdge.midY),
        screenFrame: screen
    )
    #expect(limited.maxX <= screen.maxX + 0.01)
    #expect(limited.minX >= screen.minX - 0.01)
    #expect(abs(limited.minX - nearEdge.minX) < 0.01)
    #expect(limited.maxY <= screen.maxY + 0.01)
    #expect(limited.minY >= screen.minY - 0.01)
}

@Test func resizeHitTestingUsesTheEdgesAndCorners() {
    let size = PetMetrics.size
    #expect(petResizeEdge(at: CGPoint(x: 8, y: 64), in: size) == .left)
    #expect(petResizeEdge(at: CGPoint(x: size.width - 8, y: 64), in: size) == .right)
    #expect(petResizeEdge(at: CGPoint(x: 50, y: 8), in: size) == .bottom)
    #expect(petResizeEdge(at: CGPoint(x: 50, y: size.height - 8), in: size) == .top)
    #expect(petResizeEdge(at: CGPoint(x: 8, y: size.height - 8), in: size) == .topLeft)
    #expect(petResizeEdge(at: CGPoint(x: size.width - 8, y: 8), in: size) == .bottomRight)
    #expect(petResizeEdge(at: CGPoint(x: 50, y: 64), in: size) == nil)
}

@Test func petContentFillsThePanel() {
    #expect(petContentScale(in: .zero, fallback: 1.4) == 1.4)
    #expect(abs(petContentScale(in: PetMetrics.size, fallback: 1) - 1) < 0.001)
    #expect(abs(petContentScale(in: CGSize(width: 208, height: 256), fallback: 1) - 2) < 0.001)
}

@MainActor
@Test func petKeepsItsScale() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    let preferences = PetPreferences(defaults: defaults)
    let id = preferences.pets[0].id
    let counter = ChangeCounter()
    preferences.onPetsChanged = { counter.count += 1 }
    #expect(preferences.scale(for: id) == 1)
    #expect(preferences.pets[0].scale == nil)

    preferences.setPlacement(origin: CGPoint(x: 20, y: 30), scale: 9, for: id)
    #expect(counter.count == 0)
    #expect(abs(preferences.scale(for: id) - PetMetrics.maximumScale) < 0.001)
    #expect(preferences.origin(for: id) == CGPoint(x: 20, y: 30))

    preferences.setPlacement(origin: CGPoint(x: 20, y: 30), scale: 0.1, for: id)
    let restored = PetPreferences(defaults: defaults)
    #expect(abs(restored.scale(for: id) - PetMetrics.minimumScale) < 0.001)
    #expect(restored.origin(for: id) == CGPoint(x: 20, y: 30))
    #expect(restored.pets[0].id == id)
}

@MainActor
@Test func petPanelOpensAtTheStoredScale() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let defaults = suite.defaults
    let preferences = PetPreferences(defaults: defaults)
    let id = preferences.pets[0].id
    preferences.setPlacement(origin: CGPoint(x: 40, y: 50), scale: PetMetrics.maximumScale, for: id)
    let panel = PetPanelController(
        petID: id,
        preferences: preferences,
        content: PetView(
            state: ActivityState(),
            preferences: preferences,
            library: PetModelLibrary(
                directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                codexDirectory: nil
            ),
            petID: id
        )
    )
    panel.place(on: CGRect(x: 0, y: 0, width: 1_000, height: 800))
    let expected = PetMetrics.size(for: PetMetrics.maximumScale)
    #expect(abs(panel.window.frame.width - expected.width) < 0.5)
    #expect(abs(panel.window.frame.height - expected.height) < 0.5)
    #expect(abs(panel.window.frame.origin.x - 40) < 0.5)
    #expect(abs(panel.window.frame.origin.y - 50) < 0.5)
    #expect(preferences.origin(for: id) == CGPoint(x: 40, y: 50))

    panel.show()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    panel.window.layoutIfNeeded()
    let content = try #require(panel.window.contentView)
    content.layoutSubtreeIfNeeded()
    let rendered = NSImage(size: content.bounds.size)
    rendered.lockFocus()
    if let context = NSGraphicsContext.current?.cgContext {
        content.layer?.render(in: context)
    }
    rendered.unlockFocus()
    guard let tiff = rendered.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        Issue.record("The panel did not render")
        return
    }
    var painted = 0
    var y = 0
    while y < rep.pixelsHigh {
        var x = 0
        while x < rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.3 {
                painted += 1
            }
            x += 8
        }
        y += 8
    }
    #expect(painted > 10)
    panel.hide()
}

@MainActor
@Test func largerPanelStillDrawsThePet() throws {
    let suite = try temporaryDefaults()
    defer { suite.close() }
    let preferences = PetPreferences(defaults: suite.defaults)
    let id = preferences.pets[0].id
    let size = PetMetrics.size(for: PetMetrics.maximumScale)
    let view = PetView(
        state: ActivityState(),
        preferences: preferences,
        library: PetModelLibrary(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            codexDirectory: nil
        ),
        petID: id
    )
    .frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = try #require(renderer.nsImage)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        Issue.record("The pet image has no bitmap")
        return
    }
    var painted = 0
    let step = 6
    var y = 0
    while y < rep.pixelsHigh {
        var x = 0
        while x < rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.3 {
                painted += 1
            }
            x += step
        }
        y += step
    }
    #expect(painted > 30)
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
