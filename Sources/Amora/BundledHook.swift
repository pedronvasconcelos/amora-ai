import Foundation

enum BundledHook {
    static func url(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "sh")
            ?? Bundle.module.url(forResource: name, withExtension: "sh")
    }
}
