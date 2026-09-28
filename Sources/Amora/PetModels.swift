import CoreGraphics
import Foundation
import ImageIO

struct PetModelManifest: Codable, Equatable {
    var id: String
    var displayName: String
    var description: String
    var spritesheetPath: String
    var spriteVersionNumber: Int?

    var spriteVersion: Int { spriteVersionNumber ?? 1 }
}

enum PetAnimation: Int, CaseIterable, Identifiable {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .idle: "idle"
        case .runningRight: "running-right"
        case .runningLeft: "running-left"
        case .waving: "waving"
        case .jumping: "jumping"
        case .failed: "failed"
        case .waiting: "waiting"
        case .running: "running"
        case .review: "review"
        }
    }
}

func petAnimation(for pose: PetPose) -> PetAnimation {
    switch pose {
    case .resting: .idle
    case .thinking: .review
    case .working: .running
    case .waiting: .waiting
    case .finished: .jumping
    case .reminding: .waving
    }
}

func spriteFrameIndex(elapsed: TimeInterval, frameDuration: TimeInterval, frameCount: Int) -> Int {
    guard frameCount > 0, frameDuration > 0, elapsed > 0 else { return 0 }
    return Int(elapsed / frameDuration) % frameCount
}

enum PetAtlas {
    static let columns = 8
    static let cellWidth = 192
    static let cellHeight = 208

    static func rows(version: Int) -> Int {
        version >= 2 ? 11 : 9
    }

    static func width(version: Int) -> Int {
        columns * cellWidth
    }

    static func height(version: Int) -> Int {
        rows(version: version) * cellHeight
    }
}

enum PetModelError: LocalizedError, Equatable {
    case noFiles
    case missingManifest
    case unreadableManifest
    case missingField(String)
    case invalidID(String)
    case invalidSpritesheetPath(String)
    case unsupportedVersion
    case missingSpritesheet(String)
    case unreadableSpritesheet
    case wrongSize(expectedWidth: Int, expectedHeight: Int, width: Int, height: Int)
    case emptyAnimation(String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            "Drop pet.json and the spritesheet, or the folder that contains them."
        case .missingManifest:
            "pet.json was not found."
        case .unreadableManifest:
            "pet.json is not a valid JSON object."
        case .missingField(let field):
            "pet.json needs a non-empty \"\(field)\"."
        case .invalidID(let id):
            "\"\(id)\" is not a valid id. Use letters, numbers, dots, dashes, or underscores."
        case .invalidSpritesheetPath(let path):
            "spritesheetPath \"\(path)\" must be a path inside the pet folder."
        case .unsupportedVersion:
            "spriteVersionNumber must be 1 or 2."
        case .missingSpritesheet(let path):
            "The spritesheet \"\(path)\" was not found. Drop it together with pet.json."
        case .unreadableSpritesheet:
            "The spritesheet could not be read. Use a transparent PNG or WebP."
        case .wrongSize(let expectedWidth, let expectedHeight, let width, let height):
            "The spritesheet is \(width)×\(height). This version needs exactly \(expectedWidth)×\(expectedHeight)."
        case .emptyAnimation(let name):
            "The \"\(name)\" row has no frames. Each animation row needs a frame starting in the first column."
        }
    }
}

struct PetSprite {
    let rows: [[CGImage]]

    func frames(for animation: PetAnimation) -> [CGImage] {
        rows.indices.contains(animation.rawValue) ? rows[animation.rawValue] : []
    }

    var thumbnail: CGImage? { rows.first?.first }
}

struct PetModelDraft {
    let manifest: PetModelManifest
    let spritesheetURL: URL
    let sprite: PetSprite
}

struct PetModel: Identifiable {
    enum Source: Equatable {
        case amora
        case codex
    }

    let manifest: PetModelManifest
    let directory: URL
    let sprite: PetSprite
    let source: Source

    var id: String { manifest.id }
}

enum PetModelImporter {
    static let manifestName = "pet.json"
    static let imageExtensions: Set<String> = ["webp", "png"]

    static func inspect(_ urls: [URL], fileManager: FileManager = .default) throws -> PetModelDraft {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { throw PetModelError.noFiles }

        let folder = files.count == 1 && isDirectory(files[0], fileManager: fileManager) ? files[0] : nil
        let manifestURL: URL?
        if let folder {
            manifestURL = folder.appending(path: manifestName)
        } else {
            let jsonFiles = files.filter { $0.pathExtension.lowercased() == "json" }
            manifestURL = jsonFiles.first { $0.lastPathComponent.lowercased() == manifestName }
                ?? (jsonFiles.count == 1 ? jsonFiles[0] : nil)
        }
        guard let manifestURL, let data = try? Data(contentsOf: manifestURL) else {
            throw PetModelError.missingManifest
        }
        let manifest = try parseManifest(data)

        let spritesheetURL: URL
        if let folder {
            spritesheetURL = folder.appending(path: manifest.spritesheetPath)
        } else {
            let images = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            let name = (manifest.spritesheetPath as NSString).lastPathComponent
            spritesheetURL = images.first { $0.lastPathComponent == name }
                ?? (images.count == 1 ? images[0] : nil)
                ?? manifestURL.deletingLastPathComponent().appending(path: manifest.spritesheetPath)
        }
        guard fileManager.fileExists(atPath: spritesheetURL.path) else {
            throw PetModelError.missingSpritesheet(manifest.spritesheetPath)
        }
        let sprite = try loadSprite(at: spritesheetURL, version: manifest.spriteVersion)
        return PetModelDraft(manifest: manifest, spritesheetURL: spritesheetURL, sprite: sprite)
    }

    static func parseManifest(_ data: Data) throws -> PetModelManifest {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PetModelError.unreadableManifest
        }
        func text(_ key: String) throws -> String {
            guard let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                throw PetModelError.missingField(key)
            }
            return value
        }
        let id = try text("id")
        guard isValidID(id) else { throw PetModelError.invalidID(id) }
        let displayName = try text("displayName")
        let description = try text("description")
        let spritesheetPath = try text("spritesheetPath")
        guard isContainedPath(spritesheetPath) else {
            throw PetModelError.invalidSpritesheetPath(spritesheetPath)
        }
        var version: Int?
        if let raw = object["spriteVersionNumber"] {
            guard let number = raw as? Int, number == 1 || number == 2 else {
                throw PetModelError.unsupportedVersion
            }
            version = number
        }
        return PetModelManifest(
            id: id,
            displayName: displayName,
            description: description,
            spritesheetPath: spritesheetPath,
            spriteVersionNumber: version
        )
    }

    static func loadSprite(at url: URL, version: Int) throws -> PetSprite {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PetModelError.unreadableSpritesheet
        }
        return try sprite(from: image, version: version)
    }

    static func sprite(from image: CGImage, version: Int) throws -> PetSprite {
        let width = PetAtlas.width(version: version)
        let height = PetAtlas.height(version: version)
        guard image.width == width, image.height == height else {
            throw PetModelError.wrongSize(
                expectedWidth: width,
                expectedHeight: height,
                width: image.width,
                height: image.height
            )
        }
        let alpha = try alphaValues(of: image)
        var rows: [[CGImage]] = []
        for row in 0..<PetAtlas.rows(version: version) {
            var frames: [CGImage] = []
            for column in 0..<PetAtlas.columns {
                let cell = CGRect(
                    x: column * PetAtlas.cellWidth,
                    y: row * PetAtlas.cellHeight,
                    width: PetAtlas.cellWidth,
                    height: PetAtlas.cellHeight
                )
                guard cellHasPixels(cell, alpha: alpha, rowWidth: width),
                      let frame = image.cropping(to: cell) else { break }
                frames.append(frame)
            }
            if frames.isEmpty, let animation = PetAnimation(rawValue: row) {
                throw PetModelError.emptyAnimation(animation.name)
            }
            rows.append(frames)
        }
        return PetSprite(rows: rows)
    }

    private static func alphaValues(of image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw PetModelError.unreadableSpritesheet }
        return pixels
    }

    private static func cellHasPixels(_ cell: CGRect, alpha pixels: [UInt8], rowWidth: Int) -> Bool {
        for y in Int(cell.minY)..<Int(cell.maxY) {
            let start = y * rowWidth
            for x in Int(cell.minX)..<Int(cell.maxX) where pixels[(start + x) * 4 + 3] > 8 {
                return true
            }
        }
        return false
    }

    private static func isValidID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil
    }

    private static func isContainedPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        return !path.split(separator: "/").contains("..")
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

@MainActor
final class PetModelLibrary: ObservableObject {
    @Published private(set) var models: [PetModel] = []
    let directory: URL
    let codexDirectory: URL?
    private let fileManager: FileManager
    private var registered: [PetModel] = []
    private var codex: [PetModel] = []

    init(
        directory: URL = PetModelLibrary.defaultDirectory(),
        codexDirectory: URL? = PetModelLibrary.defaultCodexDirectory(),
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.codexDirectory = codexDirectory
        self.fileManager = fileManager
        reload()
    }

    nonisolated static func defaultDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appending(path: "Library/Application Support/Amora/pets", directoryHint: .isDirectory)
    }

    nonisolated static func defaultCodexDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let codexHome = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appending(path: ".codex", directoryHint: .isDirectory)
        return codexHome.appending(path: "pets", directoryHint: .isDirectory)
    }

    func model(id: String?) -> PetModel? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }

    func contains(id: String) -> Bool {
        registered.contains { $0.id == id }
    }

    func reload() {
        registered = loadModels(in: directory, source: .amora)
        codex = codexDirectory.map { loadModels(in: $0, source: .codex) } ?? []
        publish()
    }

    @discardableResult
    func register(_ draft: PetModelDraft) throws -> PetModel {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = draft.spritesheetURL.pathExtension.lowercased()
        let spritesheetName = "spritesheet.\(fileExtension.isEmpty ? "webp" : fileExtension)"
        var manifest = draft.manifest
        manifest.spritesheetPath = spritesheetName
        let destination = directory.appending(path: manifest.id, directoryHint: .isDirectory)
        let staging = directory.appending(path: ".\(manifest.id)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: draft.spritesheetURL, to: staging.appending(path: spritesheetName))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: staging.appending(path: PetModelImporter.manifestName), options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        let model = PetModel(manifest: manifest, directory: destination, sprite: draft.sprite, source: .amora)
        registered = registered.filter { $0.id != model.id } + [model]
        publish()
        return model
    }

    func remove(id: String) throws {
        guard let model = registered.first(where: { $0.id == id }) else { return }
        if fileManager.fileExists(atPath: model.directory.path) {
            try fileManager.removeItem(at: model.directory)
        }
        registered.removeAll { $0.id == id }
        publish()
    }

    private func loadModels(in folder: URL, source: PetModel.Source) -> [PetModel] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.compactMap { entry in
            guard let draft = try? PetModelImporter.inspect([entry], fileManager: fileManager),
                  source == .codex || draft.manifest.id == entry.lastPathComponent else { return nil }
            return PetModel(manifest: draft.manifest, directory: entry, sprite: draft.sprite, source: source)
        }
    }

    private func publish() {
        var seen = Set(registered.map(\.id))
        let fromCodex = codex.filter { seen.insert($0.id).inserted }
        models = (registered + fromCodex).sorted {
            $0.manifest.displayName.localizedStandardCompare($1.manifest.displayName) == .orderedAscending
        }
    }
}
