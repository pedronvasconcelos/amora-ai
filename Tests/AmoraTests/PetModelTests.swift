import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Amora

private let standardFrames = [6, 8, 8, 4, 5, 8, 6, 6, 6]

@Test func inspectsACodexPetFolder() throws {
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writePackage(in: folder, manifest: manifest(spritesheetPath: "spritesheet.png"), sheetName: "spritesheet.png")

    let draft = try PetModelImporter.inspect([folder])
    #expect(draft.manifest == PetModelManifest(
        id: "codie",
        displayName: "Codie",
        description: "A tiny robot.",
        spritesheetPath: "spritesheet.png",
        spriteVersionNumber: nil
    ))
    #expect(draft.manifest.spriteVersion == 1)
    #expect(draft.sprite.rows.map(\.count) == standardFrames)
    #expect(draft.sprite.frames(for: .review).count == 6)
    #expect(draft.sprite.thumbnail?.width == PetAtlas.cellWidth)
    #expect(draft.sprite.thumbnail?.height == PetAtlas.cellHeight)
}

@Test func inspectsDroppedFilesEvenWhenTheSpritesheetIsRenamed() throws {
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writePackage(in: folder, manifest: manifest(), sheetName: "atlas.png")

    let draft = try PetModelImporter.inspect([
        folder.appending(path: "atlas.png"),
        folder.appending(path: "pet.json")
    ])
    #expect(draft.spritesheetURL.lastPathComponent == "atlas.png")
    #expect(draft.sprite.rows.map(\.count) == standardFrames)
}

@Test func inspectsVersionTwoAtlases() throws {
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writePackage(
        in: folder,
        manifest: manifest(spritesheetPath: "spritesheet.png", version: 2),
        sheetName: "spritesheet.png",
        image: makeAtlas(version: 2, frames: standardFrames + [8, 8])
    )

    let draft = try PetModelImporter.inspect([folder])
    #expect(draft.manifest.spriteVersion == 2)
    #expect(draft.sprite.rows.map(\.count) == standardFrames + [8, 8])
}

@Test func rejectsPackagesThatDoNotMatchTheCodexFormat() throws {
    #expect(throws: PetModelError.noFiles) { try PetModelImporter.inspect([]) }
    #expect(throws: PetModelError.unreadableManifest) {
        try PetModelImporter.parseManifest(Data("[]".utf8))
    }
    #expect(throws: PetModelError.missingField("description")) {
        try PetModelImporter.parseManifest(json(manifest(description: " ")))
    }
    #expect(throws: PetModelError.invalidID("../codie")) {
        try PetModelImporter.parseManifest(json(manifest(id: "../codie")))
    }
    #expect(throws: PetModelError.invalidSpritesheetPath("../sheet.webp")) {
        try PetModelImporter.parseManifest(json(manifest(spritesheetPath: "../sheet.webp")))
    }
    #expect(throws: PetModelError.unsupportedVersion) {
        try PetModelImporter.parseManifest(json(manifest(version: 3)))
    }

    #expect(throws: PetModelError.wrongSize(expectedWidth: 1536, expectedHeight: 2288, width: 1536, height: 1872)) {
        try PetModelImporter.sprite(from: makeAtlas(frames: standardFrames), version: 2)
    }
    #expect(throws: PetModelError.emptyAnimation("review")) {
        try PetModelImporter.sprite(from: makeAtlas(frames: Array(standardFrames.prefix(8))), version: 1)
    }

    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(throws: PetModelError.missingManifest) { try PetModelImporter.inspect([folder]) }
    try json(manifest()).write(to: folder.appending(path: "pet.json"))
    #expect(throws: PetModelError.missingSpritesheet("spritesheet.webp")) {
        try PetModelImporter.inspect([folder])
    }
}

@MainActor
@Test func libraryRegistersReloadsAndRemovesModels() throws {
    let source = try temporaryDirectory()
    let libraryDirectory = try temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: libraryDirectory)
    }
    try writePackage(in: source, manifest: manifest(), sheetName: "codie.png")
    let library = PetModelLibrary(directory: libraryDirectory, codexDirectory: nil)
    #expect(library.models.isEmpty)

    let draft = try PetModelImporter.inspect([
        source.appending(path: "pet.json"),
        source.appending(path: "codie.png")
    ])
    let model = try library.register(draft)
    let installed = libraryDirectory.appending(path: "codie")
    #expect(model.directory.standardizedFileURL == installed.standardizedFileURL)
    #expect(library.models.map(\.id) == ["codie"])
    #expect(FileManager.default.fileExists(atPath: installed.appending(path: "spritesheet.png").path))
    let stored = try PetModelImporter.parseManifest(Data(contentsOf: installed.appending(path: "pet.json")))
    #expect(stored.spritesheetPath == "spritesheet.png")
    #expect(stored.displayName == "Codie")

    let reloaded = PetModelLibrary(directory: libraryDirectory, codexDirectory: nil)
    #expect(reloaded.models.map(\.id) == ["codie"])
    #expect(reloaded.model(id: "codie")?.source == .amora)
    #expect(reloaded.model(id: "codie")?.sprite.rows.map(\.count) == standardFrames)

    try library.register(draft)
    #expect(library.models.count == 1)
    let entries = try FileManager.default.contentsOfDirectory(atPath: libraryDirectory.path)
    #expect(entries == ["codie"])

    try library.remove(id: "codie")
    #expect(library.models.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: installed.path))
    #expect(PetModelLibrary(directory: libraryDirectory, codexDirectory: nil).models.isEmpty)
}

@MainActor
@Test func libraryListsPetsInstalledForCodex() throws {
    let libraryDirectory = try temporaryDirectory()
    let codexDirectory = try temporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: libraryDirectory)
        try? FileManager.default.removeItem(at: codexDirectory)
    }
    let codexPet = codexDirectory.appending(path: "codie", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: codexPet, withIntermediateDirectories: true)
    try writePackage(in: codexPet, manifest: manifest(spritesheetPath: "spritesheet.png"), sheetName: "spritesheet.png")
    let broken = codexDirectory.appending(path: "broken", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try json(manifest()).write(to: broken.appending(path: "pet.json"))

    let library = PetModelLibrary(directory: libraryDirectory, codexDirectory: codexDirectory)
    #expect(library.models.map(\.id) == ["codie"])
    #expect(library.model(id: "codie")?.source == .codex)
    #expect(library.contains(id: "codie") == false)

    try library.remove(id: "codie")
    #expect(FileManager.default.fileExists(atPath: codexPet.path))
    #expect(library.model(id: "codie")?.source == .codex)

    let draft = try PetModelImporter.inspect([codexPet])
    try library.register(draft)
    #expect(library.models.map(\.id) == ["codie"])
    #expect(library.model(id: "codie")?.source == .amora)

    try library.remove(id: "codie")
    #expect(library.model(id: "codie")?.source == .codex)

    let home = URL(fileURLWithPath: "/Users/amora", isDirectory: true)
    #expect(PetModelLibrary.defaultCodexDirectory(home: home, environment: [:]).path == "/Users/amora/.codex/pets")
    #expect(PetModelLibrary.defaultCodexDirectory(home: home, environment: ["CODEX_HOME": "/tmp/codex"]).path == "/tmp/codex/pets")
}

@Test func mapsPetPosesToCodexAnimationRows() {
    #expect(petAnimation(for: .resting) == .idle)
    #expect(petAnimation(for: .thinking) == .review)
    #expect(petAnimation(for: .working) == .running)
    #expect(petAnimation(for: .waiting) == .waiting)
    #expect(petAnimation(for: .finished) == .jumping)
    #expect(PetAnimation.allCases.map(\.name) == [
        "idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"
    ])
    #expect(spriteFrameIndex(elapsed: 0, frameDuration: 0.1, frameCount: 6) == 0)
    #expect(spriteFrameIndex(elapsed: 0.25, frameDuration: 0.1, frameCount: 6) == 2)
    #expect(spriteFrameIndex(elapsed: 0.65, frameDuration: 0.1, frameCount: 6) == 0)
    #expect(spriteFrameIndex(elapsed: 1, frameDuration: 0.1, frameCount: 0) == 0)
    #expect(PetAtlas.width(version: 1) == 1536)
    #expect(PetAtlas.height(version: 1) == 1872)
    #expect(PetAtlas.height(version: 2) == 2288)
}

private func manifest(
    id: String = "codie",
    description: String = "A tiny robot.",
    spritesheetPath: String = "spritesheet.webp",
    version: Int? = nil
) -> [String: Any] {
    var manifest: [String: Any] = [
        "id": id,
        "displayName": "Codie",
        "description": description,
        "spritesheetPath": spritesheetPath
    ]
    if let version {
        manifest["spriteVersionNumber"] = version
    }
    return manifest
}

private func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

private func writePackage(
    in folder: URL,
    manifest: [String: Any],
    sheetName: String,
    image: CGImage? = nil
) throws {
    try json(manifest).write(to: folder.appending(path: "pet.json"))
    try writePNG(image ?? makeAtlas(frames: standardFrames), to: folder.appending(path: sheetName))
}

private func makeAtlas(version: Int = 1, frames: [Int]) throws -> CGImage {
    let width = PetAtlas.width(version: version)
    let height = PetAtlas.height(version: version)
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.93, green: 0.47, blue: 0.33, alpha: 1))
    for (row, count) in frames.enumerated() {
        for column in 0..<count {
            let top = row * PetAtlas.cellHeight + 60
            context.fill(CGRect(
                x: column * PetAtlas.cellWidth + 60,
                y: height - top - 80,
                width: 70,
                height: 80
            ))
        }
    }
    return try #require(context.makeImage())
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "amora-pet-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
