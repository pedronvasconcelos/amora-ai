import Foundation
import Testing
@testable import Amora

@Test func cursorInstallationIsIdempotentAndRemovalPreservesOtherHooks() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appending(path: ".cursor")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configuration = directory.appending(path: "hooks.json")
    let original: [String: Any] = [
        "version": 1,
        "custom": ["enabled": true],
        "hooks": [
            "stop": [["command": "echo '{}'", "type": "command"]],
            "sessionStart": [["command": "echo hello"]]
        ]
    ]
    try JSONSerialization.data(withJSONObject: original).write(to: configuration)
    let integration = CursorHooks(home: home)
    try integration.install()
    let first = try Data(contentsOf: configuration)
    try integration.install()
    #expect(try Data(contentsOf: configuration) == first)
    let document = try readDocument(configuration)
    #expect(document["version"] as? Int == 1)
    let hooks = try #require(document["hooks"] as? [String: [[String: Any]]])
    #expect(hooks["stop"]?.count == 2)
    #expect(hooks["beforeSubmitPrompt"]?.count == 1)
    #expect(hooks["afterFileEdit"]?.count == 1)
    #expect(hooks["sessionStart"]?.count == 1)
    try integration.remove()
    #expect(try NSDictionary(dictionary: readDocument(configuration)).isEqual(to: original))
    try integration.remove()
    #expect(try NSDictionary(dictionary: readDocument(configuration)).isEqual(to: original))
}

@Test func cursorInstallAddsSchemaVersionWithoutDroppingSettings() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appending(path: ".cursor")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configuration = directory.appending(path: "hooks.json")
    try JSONSerialization.data(withJSONObject: ["custom": ["enabled": true]]).write(to: configuration)
    let integration = CursorHooks(home: home)
    try integration.install()
    let installed = try readDocument(configuration)
    #expect(installed["version"] as? Int == 1)
    #expect(NSDictionary(dictionary: installed["custom"] as? [String: Any] ?? [:]).isEqual(to: ["enabled": true]))
    try integration.remove()
    let removed = try readDocument(configuration)
    #expect(removed["version"] as? Int == 1)
    #expect(NSDictionary(dictionary: removed["custom"] as? [String: Any] ?? [:]).isEqual(to: ["enabled": true]))
    let hooks = try #require(removed["hooks"] as? [String: Any])
    #expect(hooks.isEmpty)
}

@Test func invalidCursorConfigurationIsNeverOverwritten() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appending(path: ".cursor")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configuration = directory.appending(path: "hooks.json")
    let integration = CursorHooks(home: home)
    for text in [
        "invalid",
        "[]",
        #"{"version":true}"#,
        #"{"version":2}"#,
        #"{"hooks":[]}"#,
        #"{"hooks":{"stop":"invalid"}}"#,
        #"{"hooks":{"stop":["invalid"]}}"#
    ] {
        let original = Data(text.utf8)
        try original.write(to: configuration)
        #expect(throws: (any Error).self) { try integration.install() }
        #expect(try Data(contentsOf: configuration) == original)
        #expect(throws: (any Error).self) { try integration.remove() }
        #expect(try Data(contentsOf: configuration) == original)
    }
}

@MainActor
@Test func installedCursorHooksDeliverOnlyActivityAndFailOpen() async throws {
    let root = try temporaryHome()
    let home = root.appending(path: "a'b")
    defer { try? FileManager.default.removeItem(at: root) }
    let integration = CursorHooks(home: home)
    try integration.install()
    let document = try readDocument(home.appending(path: ".cursor/hooks.json"))
    #expect(document["version"] as? Int == 1)
    let hooks = try #require(document["hooks"] as? [String: [[String: Any]]])
    var received: [ActivityEvent] = []
    let receiver = ActivityReceiver(directory: home.appending(path: "Library/Application Support/Pet")) {
        received.append($0)
    }
    try receiver.start()
    defer { receiver.stop() }
    let mappings: [(String, ActivityEvent.Activity)] = [
        ("beforeSubmitPrompt", .thinking), ("preToolUse", .working),
        ("afterFileEdit", .working), ("stop", .finished)
    ]
    for (event, expected) in mappings {
        let handler = try #require(hooks[event]?.first)
        let command = try #require(handler["command"] as? String)
        #expect(handler["type"] as? String == "command")
        #expect(handler["failClosed"] as? Bool == false)
        #expect(handler["timeout"] as? Int == 2)
        let output = try await runHook(command, home: home)
        #expect(output == (event == "stop" ? "{}\n" : ""))
        #expect(!output.contains("private"))
        #expect(received.last?.activity == expected)
        #expect(received.last?.source == .cursor)
    }
    #expect(received.count == 4)
    receiver.stop()
    let handler = try #require(hooks["stop"]?.first)
    let command = try #require(handler["command"] as? String)
    #expect(try await runHook(command, home: home) == "{}\n")
}
