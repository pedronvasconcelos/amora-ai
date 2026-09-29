import Foundation
import Testing
@testable import Amora

@Test func claudeInstallationIsIdempotentAndRemovalPreservesOtherHooks() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let claudeHome = home.appending(path: "custom-claude")
    try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
    let configuration = claudeHome.appending(path: "settings.json")
    let original: [String: Any] = [
        "permissions": ["allow": ["Bash(git *)"]],
        "model": "claude",
        "hooks": [
            "Stop": [["matcher": "*", "hooks": [["type": "command", "command": "echo '{}'"]]]],
            "SessionStart": [["hooks": [["type": "command", "command": "echo hello"]]]]
        ]
    ]
    try JSONSerialization.data(withJSONObject: original).write(to: configuration)
    let integration = ClaudeHooks(home: home, environment: ["CLAUDE_CONFIG_DIR": claudeHome.path])
    #expect(try integration.isInstalled() == false)
    try integration.install()
    let first = try Data(contentsOf: configuration)
    try integration.install()
    #expect(try Data(contentsOf: configuration) == first)
    let hooks = try #require(readDocument(configuration)["hooks"] as? [String: [[String: Any]]])
    #expect(hooks["Stop"]?.count == 2)
    #expect(hooks["UserPromptSubmit"]?.count == 1)
    #expect(hooks["PermissionRequest"]?.count == 1)
    #expect(try integration.isInstalled())
    try integration.remove()
    #expect(try integration.isInstalled() == false)
    #expect(try NSDictionary(dictionary: readDocument(configuration)).isEqual(to: original))
    try integration.remove()
    #expect(try NSDictionary(dictionary: readDocument(configuration)).isEqual(to: original))
}

@Test func invalidClaudeConfigurationIsNeverOverwritten() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appending(path: ".claude")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configuration = directory.appending(path: "settings.json")
    let integration = ClaudeHooks(home: home, environment: [:])
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
@Test func installedClaudeHooksDeliverOnlyActivityAndFailOpen() async throws {
    let root = try temporaryHome()
    let home = root.appending(path: "a'b")
    defer { try? FileManager.default.removeItem(at: root) }
    let integration = ClaudeHooks(home: home, environment: [:])
    try integration.install()
    let document = try readDocument(home.appending(path: ".claude/settings.json"))
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
        #expect(handler["type"] as? String == "command")
        let before = received.count
        let output = try await runHook(command, home: home, payload: cwdProjectPayload)
        await waitUntil { received.count > before }
        #expect(output == (event == "Stop" ? "{}\n" : ""))
        #expect(!output.contains("private"))
        #expect(!output.contains("secret"))
        #expect(!output.contains("notes.txt"))
        #expect(received.last?.activity == expected)
        #expect(received.last?.source == .claude)
        #expect(received.last?.project == "amora-ai")
    }
    #expect(received.count == 4)
    receiver.stop()
    let group = try #require(hooks["Stop"]?.first)
    let handler = try #require((group["hooks"] as? [[String: Any]])?.first)
    let command = try #require(handler["command"] as? String)
    let line = try await captureHookLine(home: home) {
        let output = try await runHook(command, home: home, payload: cwdProjectPayload)
        #expect(output == "{}\n")
        #expect(!output.contains("private"))
    }
    #expect(line == "{\"v\":1,\"source\":\"claude\",\"activity\":\"finished\",\"project\":\"amora-ai\"}\n")
}

@MainActor
@Test func claudeHooksReportEachSessionAndSubagent() async throws {
    let root = try temporaryHome()
    let home = root.appending(path: "a'b")
    defer { try? FileManager.default.removeItem(at: root) }
    try ClaudeHooks(home: home, environment: [:]).install()
    let hooks = try #require(readDocument(home.appending(path: ".claude/settings.json"))["hooks"] as? [String: [[String: Any]]])
    func handler(_ event: String) throws -> [String: Any] {
        let group = try #require(hooks[event]?.first)
        return try #require((group["hooks"] as? [[String: Any]])?.first)
    }
    func command(_ event: String) throws -> String {
        try #require(handler(event)["command"] as? String)
    }
    #expect(try handler("SubagentStart")["async"] as? Bool == true)
    #expect(try handler("SubagentStop")["async"] as? Bool == true)
    #expect(try handler("SessionEnd")["async"] == nil)
    #expect(try handler("SessionEnd")["timeout"] as? Int == 2)

    let subagentStop = #"{"session_id":"5c2d-11","cwd":"/tmp/secret/amora-ai","agent_id":"a-7","agent_type":"Explore","stop_hook_active":false}"#
    let received = try await deliveredEvents(home: home, [
        HookRun(command: try command("PreToolUse"), payload: claudeSessionPayload),
        HookRun(command: try command("SubagentStart"), payload: #"{"session_id":"5c2d-11","cwd":"/tmp/secret/amora-ai","agent_id":"a-7","agent_type":"Explore"}"#),
        HookRun(command: try command("PermissionRequest"), payload: claudeSubagentPayload),
        HookRun(command: try command("SubagentStop"), payload: subagentStop),
        // Without a subagent id, a SubagentStop would read as the whole session ending, so it sends nothing.
        HookRun(command: try command("SubagentStop"), payload: #"{"session_id":"5c2d-11","cwd":"/tmp/secret/amora-ai"}"#, delivers: false),
        HookRun(command: try command("SessionEnd"), payload: #"{"session_id":"5c2d-11","cwd":"/tmp/secret/amora-ai","reason":"prompt_input_exit"}"#)
    ])
    #expect(received.map(\.activity) == [.working, .working, .waiting, .finished, .finished])
    #expect(received.allSatisfy { $0.source == .claude && $0.session == "5c2d-11" && $0.project == "amora-ai" })
    #expect(received.map(\.subagent) == [nil, "a-7", "a-7", "a-7", nil])
    #expect(received.map(\.subagentType) == [nil, "Explore", "Explore", "Explore", nil])
    #expect(received.map(\.ended) == [false, false, false, true, true])
    let output = try await runHook(try command("SubagentStop"), home: home, payload: subagentStop)
    #expect(output == "{}\n")
    let line = try await captureHookLine(home: home) {
        _ = try await runHook(try command("PreToolUse"), home: home, payload: claudeSubagentPayload)
    }
    #expect(line == #"{"v":1,"source":"claude","activity":"working","project":"amora-ai","session":"5c2d-11","subagent":"a-7","subagentType":"Explore"}"# + "\n")
}
