import CoreGraphics
import Foundation

@MainActor
final class PetPreferences: ObservableObject {
    static let visibleKey = "petVisible"
    static let originXKey = "petOriginX"
    static let originYKey = "petOriginY"

    @Published private(set) var isVisible: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.visibleKey) == nil {
            isVisible = true
        } else {
            isVisible = defaults.bool(forKey: Self.visibleKey)
        }
    }

    var origin: CGPoint? {
        guard defaults.object(forKey: Self.originXKey) != nil,
              defaults.object(forKey: Self.originYKey) != nil else {
            return nil
        }
        return CGPoint(
            x: defaults.double(forKey: Self.originXKey),
            y: defaults.double(forKey: Self.originYKey)
        )
    }

    func setVisible(_ visible: Bool) {
        defaults.set(visible, forKey: Self.visibleKey)
        isVisible = visible
    }

    func setOrigin(_ origin: CGPoint) {
        defaults.set(origin.x, forKey: Self.originXKey)
        defaults.set(origin.y, forKey: Self.originYKey)
    }
}
