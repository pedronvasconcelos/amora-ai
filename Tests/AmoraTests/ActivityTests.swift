import Darwin
import Foundation
import Testing
@testable import Amora

@Test func validatesEventContract() {
    let valid = Data(#"{"v":1,"source":"cursor","activity":"thinking"}"#.utf8)
    #expect(ActivityEvent.decode(valid)?.activity == .thinking)
    for payload in [
        #"{"v":2,"source":"cursor","activity":"thinking"}"#,
        #"{"v":1,"source":"unknown","activity":"thinking"}"#,
        #"{"v":1,"source":"claude","activity":"unknown"}"#,
        #"{"source":"cursor","activity":"thinking"}"#,
        "invalid"
    ] {
        #expect(ActivityEvent.decode(Data(payload.utf8)) == nil)
    }
}

@MainActor
@Test func keepsEachAgentsActivitySeparately() throws {
    let state = ActivityState()
    #expect(state.agents.isEmpty)
    #expect(activitySummary(state.agents) == nil)
    #expect(leadingActivity(state.agents) == nil)

    for payload in [
        #"{"v":1,"source":"codex","activity":"working"}"#,
        #"{"v":1,"source":"cursor","activity":"thinking"}"#,
        #"{"v":1,"source":"claude","activity":"finished"}"#
    ] {
        state.record(try #require(ActivityEvent.decode(Data(payload.utf8))))
    }
    #expect(state.agents == [
        AgentActivity(source: .cursor, activity: .thinking),
        AgentActivity(source: .claude, activity: .finished),
        AgentActivity(source: .codex, activity: .working)
    ])
    #expect(leadingActivity(state.agents) == AgentActivity(source: .codex, activity: .working))
    #expect(activitySummary(state.agents) == "Cursor: Thinking\nClaude Code: Finished\nCodex: Working")

    state.record(try #require(ActivityEvent.decode(Data(#"{"v":1,"source":"cursor","activity":"waiting"}"#.utf8))))
    #expect(state.agents.map(\.activity) == [.waiting, .finished, .working])
    #expect(leadingActivity(state.agents)?.source == .cursor)
}

@Test func keepsOnlyTheProjectFolderName() throws {
    let named = Data(#"{"v":1,"source":"cursor","activity":"working","project":"amora-ai"}"#.utf8)
    #expect(ActivityEvent.decode(named)?.project == "amora-ai")
    let spaced = Data(#"{"v":1,"source":"claude","activity":"thinking","project":"My Project"}"#.utf8)
    #expect(ActivityEvent.decode(spaced)?.project == "My Project")

    for project in ["/Users/me/secret", "Users\\me\\secret", "..", ".", "\"quoted\"", String(repeating: "a", count: 121)] {
        let payload = try JSONSerialization.data(withJSONObject: [
            "v": 1, "source": "cursor", "activity": "working", "project": project
        ])
        let event = ActivityEvent.decode(payload)
        #expect(event?.activity == .working)
        #expect(event?.project == nil)
    }
    let omitted = Data(#"{"v":1,"source":"codex","activity":"finished"}"#.utf8)
    #expect(ActivityEvent.decode(omitted)?.project == nil)
}

@MainActor
@Test func keepsEachAgentsProjectWhenALaterEventOmitsIt() throws {
    let state = ActivityState()
    state.record(try #require(ActivityEvent.decode(Data(
        #"{"v":1,"source":"cursor","activity":"thinking","project":"amora-ai"}"#.utf8
    ))))
    state.record(try #require(ActivityEvent.decode(Data(
        #"{"v":1,"source":"codex","activity":"working","project":"other-app"}"#.utf8
    ))))
    state.record(try #require(ActivityEvent.decode(Data(
        #"{"v":1,"source":"cursor","activity":"finished"}"#.utf8
    ))))
    #expect(state.agents == [
        AgentActivity(source: .cursor, activity: .finished, project: "amora-ai"),
        AgentActivity(source: .codex, activity: .working, project: "other-app")
    ])
    #expect(activitySummary(state.agents) == "Cursor: Finished · amora-ai\nCodex: Working · other-app")
}

@Test func leadingActivityBreaksTiesByAgentOrder() {
    #expect(leadingActivity([
        AgentActivity(source: .cursor, activity: .working),
        AgentActivity(source: .codex, activity: .working)
    ])?.source == .cursor)
}

@MainActor
@Test func receivesFramedEventsAndPreservesActiveSocket() async throws {
    let directory = URL(fileURLWithPath: "/tmp/amora-\(UUID().uuidString)")
    var events: [ActivityEvent] = []
    let receiver = ActivityReceiver(directory: directory) { events.append($0) }
    try receiver.start()
    defer {
        receiver.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    let duplicate = ActivityReceiver(directory: directory) { _ in }
    #expect(throws: (any Error).self) { try duplicate.start() }
    duplicate.stop()

    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let path = directory.appending(path: "pet.sock").path
    withUnsafeMutableBytes(of: &address.sun_path) {
        $0.copyBytes(from: Array(path.utf8CString).map { UInt8(bitPattern: $0) })
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    #expect(connected == 0)
    let first = Data(#"{"v":1,"source":"cursor","activity":"thinking"}"#.utf8)
    #expect(first.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) } == first.count)
    try await Task.sleep(for: .milliseconds(150))
    #expect(events.isEmpty)
    let rest = Data(("\ninvalid\n" + #"{"v":1,"source":"claude","activity":"finished"}"# + "\n").utf8)
    #expect(rest.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) } == rest.count)
    try await Task.sleep(for: .milliseconds(200))
    #expect(events.map(\.activity) == [.thinking, .finished])
    #expect(events.last?.source == .claude)
    receiver.stop()
    #expect(!FileManager.default.fileExists(atPath: path))
    try receiver.start()
}

@MainActor
@Test func preservesNonSocketFiles() throws {
    let directory = URL(fileURLWithPath: "/tmp/amora-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appending(path: "pet.sock")
    let original = Data("keep".utf8)
    try original.write(to: path)
    let receiver = ActivityReceiver(directory: directory) { _ in }
    #expect(throws: (any Error).self) { try receiver.start() }
    #expect(try Data(contentsOf: path) == original)
}
