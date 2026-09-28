import Foundation
import Testing
@testable import Amora

@Test func installationIsIdempotentAndRemovalPreservesOtherHooks() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let codexHome = home.appending(path: "custom-codex")
    try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    let configuration = codexHome.appending(path: "hooks.json")
    let original: [String: Any] = [
        "description": "User hooks",
        "custom": ["enabled": true],
        "hooks": [
            "Stop": [["matcher": "*", "hooks": [["type": "command", "command": "echo '{}'" ]]]],
            "SessionStart": [["hooks": [["type": "command", "command": "echo hello"]]]]
        ]
    ]
    try JSONSerialization.data(withJSONObject: original).write(to: configuration)
    let integration = CodexHooks(home: home, environment: ["CODEX_HOME": codexHome.path])
    #expect(try integration.isInstalled() == false)
    try integration.install()
    let first = try Data(contentsOf: configuration)
    try integration.install()
    #expect(try Data(contentsOf: configuration) == first)
    let hooks = try #require(readDocument(configuration)["hooks"] as? [String: [[String: Any]]])
    #expect(hooks["Stop"]?.count == 2)
    #expect(hooks["UserPromptSubmit"]?.count == 1)
    #expect(try integration.isInstalled())
    try integration.remove()
    #expect(try integration.isInstalled() == false)
    #expect(try NSDictionary(dictionary: readDocument(configuration)).isEqual(to: original))
    try integration.remove()
    #expect(try NSDictionary(dictionary: readDocument(configuration)).isEqual(to: original))
}

@Test func invalidConfigurationIsNeverOverwritten() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appending(path: ".codex")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configuration = directory.appending(path: "hooks.json")
    let integration = CodexHooks(home: home, environment: [:])
    for text in ["invalid", "[]", #"{"hooks":[]}"#, #"{"hooks":{"Stop":[{"hooks":"invalid"}]}}"#] {
        let original = Data(text.utf8)
        try original.write(to: configuration)
        #expect(throws: (any Error).self) { try integration.install() }
        #expect(try Data(contentsOf: configuration) == original)
        #expect(throws: (any Error).self) { try integration.remove() }
        #expect(try Data(contentsOf: configuration) == original)
        #expect(throws: (any Error).self) { try integration.isInstalled() }
        #expect(try Data(contentsOf: configuration) == original)
    }
}

@MainActor
@Test func installedHooksDeliverOnlyActivityAndFailOpen() async throws {
    let root = try temporaryHome()
    let home = root.appending(path: "a'b")
    defer { try? FileManager.default.removeItem(at: root) }
    let integration = CodexHooks(home: home, environment: [:])
    try integration.install()
    let document = try readDocument(home.appending(path: ".codex/hooks.json"))
    let hooks = try #require(document["hooks"] as? [String: [[String: Any]]])
    var received: [ActivityEvent] = []
    let receiver = ActivityReceiver(directory: home.appending(path: "Library/Application Support/Pet")) {
        received.append($0)
    }
    try receiver.start()
    defer { receiver.stop() }
    let mappings: [(String, ActivityEvent.Activity)] = [
        ("UserPromptSubmit", .thinking), ("PreToolUse", .working),
        ("PermissionRequest", .waiting), ("Stop", .finished)
    ]
    for (event, expected) in mappings {
        let group = try #require(hooks[event]?.first)
        let handler = try #require((group["hooks"] as? [[String: Any]])?.first)
        let command = try #require(handler["command"] as? String)
        #expect(handler["async"] as? Bool == true)
        let output = try await runHook(command, home: home)
        #expect(output == (event == "Stop" ? "{}\n" : ""))
        #expect(received.last?.activity == expected)
        #expect(received.last?.source == .codex)
    }
    #expect(received.count == 4)
    receiver.stop()
    let group = try #require(hooks["Stop"]?.first)
    let handler = try #require((group["hooks"] as? [[String: Any]])?.first)
    let command = try #require(handler["command"] as? String)
    #expect(try await runHook(command, home: home) == "{}\n")
}

