import CoreGraphics
import Foundation

struct DesktopPet: Codable, Identifiable, Equatable {
    var id: UUID
    var originX: Double?
    var originY: Double?
    var isVisible: Bool
    var modelID: String?

    var origin: CGPoint? {
        guard let originX, let originY else { return nil }
        return CGPoint(x: originX, y: originY)
    }

    init(id: UUID = UUID(), origin: CGPoint? = nil, isVisible: Bool, modelID: String? = nil) {
        self.id = id
        self.originX = origin.map { Double($0.x) }
        self.originY = origin.map { Double($0.y) }
        self.isVisible = isVisible
        self.modelID = modelID
    }
}

func nextPetOrigin(after origin: CGPoint?, windowSize: CGSize, screenFrame: CGRect) -> CGPoint {
    let base = origin ?? defaultPetOrigin(windowSize: windowSize, screenFrame: screenFrame)
    return clampedPetOrigin(
        CGPoint(x: base.x - 36, y: base.y + 36),
        windowSize: windowSize,
        screenFrame: screenFrame
    )
}

@MainActor
final class PetPreferences: ObservableObject {
    static let petsKey = "desktopPets"
    static let activePetIDKey = "activePetID"
    static let visibleKey = "petVisible"
    static let originXKey = "petOriginX"
    static let originYKey = "petOriginY"
    static let maximumPets = 6

    @Published private(set) var pets: [DesktopPet]
    @Published private(set) var activePetID: UUID
    var onPetsChanged: (@MainActor () -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.load(from: defaults)
        pets = stored.pets
        activePetID = stored.activePetID
        if stored.shouldPersist {
            persist()
        }
    }

    var canAddPet: Bool { pets.count < Self.maximumPets }
    var canRemovePet: Bool { pets.count > 1 }

    var activePet: DesktopPet? {
        pet(activePetID)
    }

    func pet(_ id: UUID) -> DesktopPet? {
        pets.first { $0.id == id }
    }

    func origin(for id: UUID) -> CGPoint? {
        pet(id)?.origin
    }

    func addPet(modelID: String? = nil, windowSize: CGSize, screenFrame: CGRect) {
        guard canAddPet else { return }
        let origin = nextPetOrigin(after: pets.last?.origin, windowSize: windowSize, screenFrame: screenFrame)
        let pet = DesktopPet(id: UUID(), origin: origin, isVisible: true, modelID: modelID)
        pets.append(pet)
        activePetID = pet.id
        persist()
        onPetsChanged?()
    }

    func removePet(_ id: UUID) {
        guard canRemovePet, let index = pets.firstIndex(where: { $0.id == id }) else { return }
        pets.remove(at: index)
        if activePetID == id {
            activePetID = pets[min(index, pets.count - 1)].id
        }
        persist()
        onPetsChanged?()
    }

    func setModel(_ modelID: String?, for id: UUID) {
        guard let index = pets.firstIndex(where: { $0.id == id }), pets[index].modelID != modelID else { return }
        pets[index].modelID = modelID
        persist()
    }

    func clearModel(_ modelID: String) {
        guard pets.contains(where: { $0.modelID == modelID }) else { return }
        for index in pets.indices where pets[index].modelID == modelID {
            pets[index].modelID = nil
        }
        persist()
    }

    func setActive(_ id: UUID) {
        guard pets.contains(where: { $0.id == id }), activePetID != id else { return }
        activePetID = id
        persist()
    }

    func setVisible(_ visible: Bool, for id: UUID) {
        guard let index = pets.firstIndex(where: { $0.id == id }), pets[index].isVisible != visible else { return }
        pets[index].isVisible = visible
        persist()
        onPetsChanged?()
    }

    func setOrigin(_ origin: CGPoint, for id: UUID) {
        guard let index = pets.firstIndex(where: { $0.id == id }) else { return }
        pets[index].originX = Double(origin.x)
        pets[index].originY = Double(origin.y)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pets) else { return }
        defaults.set(data, forKey: Self.petsKey)
        defaults.set(activePetID.uuidString, forKey: Self.activePetIDKey)
    }

    private struct StoredPets {
        var pets: [DesktopPet]
        var activePetID: UUID
        var shouldPersist: Bool
    }

    private static func load(from defaults: UserDefaults) -> StoredPets {
        if let data = defaults.data(forKey: petsKey),
           let decoded = try? JSONDecoder().decode([DesktopPet].self, from: data),
           let first = decoded.first {
            let storedID = defaults.string(forKey: activePetIDKey).flatMap(UUID.init(uuidString:))
            let active = storedID.flatMap { id in decoded.contains(where: { $0.id == id }) ? id : nil } ?? first.id
            return StoredPets(pets: decoded, activePetID: active, shouldPersist: active != storedID)
        }

        let visible: Bool
        if defaults.object(forKey: visibleKey) == nil {
            visible = true
        } else {
            visible = defaults.bool(forKey: visibleKey)
        }
        let origin: CGPoint?
        if defaults.object(forKey: originXKey) != nil, defaults.object(forKey: originYKey) != nil {
            origin = CGPoint(x: defaults.double(forKey: originXKey), y: defaults.double(forKey: originYKey))
        } else {
            origin = nil
        }
        let pet = DesktopPet(origin: origin, isVisible: visible)
        return StoredPets(pets: [pet], activePetID: pet.id, shouldPersist: true)
    }
}
