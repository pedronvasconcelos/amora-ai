import Darwin
import Foundation
import Testing
@testable import Amora

let cursorProjectPayload = """
{"workspace_roots":["/tmp/secret/amora-ai"],"cwd":"/tmp/secret/nested","prompt":"private prompt","tool_input":{"file_path":"/tmp/secret/notes.txt","content":"private contents"},"tool_output":"private result"}
"""

let cwdProjectPayload = """
{"cwd":"/tmp/secret/amora-ai","prompt":"private prompt","tool_input":{"file_path":"/tmp/secret/notes.txt","content":"private contents"},"tool_output":"private result"}
"""

func temporaryHome() throws -> URL {
    let home = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

func readDocument(_ url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

/// The activity socket is drained on a timer. Yield until that timer has delivered the event.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(1)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
func runHook(
    _ command: String,
    home: URL,
    payload: String = #"{"prompt":"private prompt","tool_input":"private contents"}"#
) async throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
    let inputURL = home.appending(path: "hook-input-\(UUID().uuidString)")
    try Data(payload.utf8).write(to: inputURL)
    defer { try? FileManager.default.removeItem(at: inputURL) }
    let input = try FileHandle(forReadingFrom: inputURL)
    defer { try? input.close() }
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let deadline = Date().addingTimeInterval(4)
    while process.isRunning && Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    if process.isRunning {
        process.terminate()
        throw CocoaError(.executableRuntimeMismatch)
    }
    #expect(process.terminationStatus == 0)
    #expect(errors.fileHandleForReading.readDataToEndOfFile().isEmpty)
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

@MainActor
func captureHookLine(home: URL, _ send: () async throws -> Void) async throws -> String {
    let directory = home.appending(path: "Library/Application Support/Pet")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appending(path: "pet.sock").path
    unlink(path)
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else { throw POSIXError(.EIO) }
    defer {
        close(listener)
        unlink(path)
    }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
    withUnsafeMutableBytes(of: &address.sun_path) {
        $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
    }
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0, listen(listener, 1) == 0 else { throw POSIXError(.EIO) }
    guard fcntl(listener, F_SETFL, O_NONBLOCK) != -1 else { throw POSIXError(.EIO) }
    try await send()
    let deadline = Date().addingTimeInterval(2)
    var client: Int32 = -1
    while client < 0, Date() < deadline {
        client = accept(listener, nil, nil)
        if client < 0 { try await Task.sleep(for: .milliseconds(20)) }
    }
    guard client >= 0 else { throw POSIXError(.ETIMEDOUT) }
    defer { close(client) }
    _ = fcntl(client, F_SETFL, O_NONBLOCK)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 2048)
    while Date() < deadline {
        let count = read(client, &buffer, buffer.count)
        if count > 0 {
            data.append(contentsOf: buffer.prefix(count))
            if data.contains(10) { break }
        } else if count == 0 {
            break
        } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
            break
        } else {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    return String(decoding: data, as: UTF8.self)
}

@MainActor
@Test func hookRunnerHandlesAnEarlyExitingChild() async throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let output = try await runHook("exit 0", home: home, payload: String(repeating: "x", count: 100_000))
    #expect(output.isEmpty)
}

/// Claude Code and Codex send the session, and inside a subagent the subagent, ahead of tool input.
/// The decoys in tool input must never be read as ids.
let claudeSessionPayload = """
{"session_id":"5c2d-11","transcript_path":"/tmp/secret/t.jsonl","cwd":"/tmp/secret/amora-ai","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"mcp__notes__read","tool_input":{"session_id":"decoy","agent_id":"decoy","agent_type":"decoy","prompt":"private prompt"}}
"""

let claudeSubagentPayload = """
{"session_id":"5c2d-11","transcript_path":"/tmp/secret/t.jsonl","cwd":"/tmp/secret/amora-ai","permission_mode":"default","agent_id":"a-7","agent_type":"Explore","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/secret/notes.txt","session_id":"decoy"}}
"""

let codexSubagentPayload = """
{"session_id":"019a-77","turn_id":"t-3","agent_id":"019b-01","agent_type":"worker","transcript_path":null,"cwd":"/tmp/secret/amora-ai","hook_event_name":"PreToolUse","model":"gpt","permission_mode":"default","tool_name":"shell","tool_input":{"command":"private command","agent_id":"decoy"}}
"""

let cursorSessionPayload = """
{"conversation_id":"conv-1","generation_id":"gen-9","model":"auto","model_params":{"session_id":"decoy"},"hook_event_name":"preToolUse","cursor_version":"2.1","workspace_roots":["/tmp/secret/amora-ai"],"tool_input":{"content":"private contents"}}
"""

/// Runs each hook command with its payload against a live receiver and returns what arrived.
@MainActor
func deliveredEvents(home: URL, _ runs: [(command: String, payload: String)]) async throws -> [ActivityEvent] {
    var received: [ActivityEvent] = []
    let receiver = ActivityReceiver(directory: home.appending(path: "Library/Application Support/Pet")) {
        received.append($0)
    }
    try receiver.start()
    defer { receiver.stop() }
    for run in runs {
        let before = received.count
        let output = try await runHook(run.command, home: home, payload: run.payload)
        #expect(!output.contains("private"))
        #expect(!output.contains("secret"))
        await waitUntil { received.count > before }
    }
    return received
}
