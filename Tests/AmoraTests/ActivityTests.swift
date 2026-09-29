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
    var noSignal: Int32 = 1
    #expect(setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0)
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

private func event(_ json: String) throws -> ActivityEvent {
    try #require(ActivityEvent.decode(Data(json.utf8)))
}

@Test func readsSessionsAndSubagentsFromEvents() throws {
    let plain = try event(#"{"v":1,"source":"claude","activity":"working"}"#)
    #expect(plain.session == nil)
    #expect(plain.subagent == nil)
    #expect(plain.ended == false)

    let subagent = try event(
        #"{"v":1,"source":"claude","activity":"finished","session":"5c2d-11:a_b.c","subagent":"a-7","subagentType":"Explore","ended":true}"#
    )
    #expect(subagent.session == "5c2d-11:a_b.c")
    #expect(subagent.subagent == "a-7")
    #expect(subagent.subagentType == "Explore")
    #expect(subagent.ended)

    let typeWithoutSubagent = try event(#"{"v":1,"source":"codex","activity":"working","session":"s1","subagentType":"worker"}"#)
    #expect(typeWithoutSubagent.subagentType == nil)

    for id in ["", "has space", "quote\"d", "slash/ed", "é", String(repeating: "a", count: 129)] {
        let payload = try JSONSerialization.data(withJSONObject: [
            "v": 1, "source": "cursor", "activity": "working", "session": id, "subagent": id
        ])
        let decoded = try #require(ActivityEvent.decode(payload))
        #expect(decoded.session == nil)
        #expect(decoded.subagent == nil)
    }
    let odd = try event(#"{"v":1,"source":"cursor","activity":"working","session":7,"ended":"yes"}"#)
    #expect(odd.session == nil)
    #expect(odd.ended == false)
}

@MainActor
@Test func keepsEachSessionOfAnAgentSeparately() throws {
    let state = ActivityState()
    try state.record(event(#"{"v":1,"source":"claude","activity":"working","project":"amora-ai","session":"s1"}"#))
    try state.record(event(#"{"v":1,"source":"claude","activity":"waiting","project":"api","session":"s2"}"#))
    try state.record(event(#"{"v":1,"source":"cursor","activity":"thinking","project":"site","session":"c1"}"#))
    #expect(state.sessions == [
        AgentActivity(source: .claude, activity: .working, project: "amora-ai", session: "s1"),
        AgentActivity(source: .claude, activity: .waiting, project: "api", session: "s2"),
        AgentActivity(source: .cursor, activity: .thinking, project: "site", session: "c1")
    ])
    // One entry per agent: the session that most needs you.
    #expect(state.agents.map(\.session) == ["c1", "s2"])
    #expect(state.rows.map(\.session) == ["c1", "s1", "s2"])
    #expect(activitySummary(state.rows) == "Cursor: Thinking · site\nClaude Code: Working · amora-ai\nClaude Code: Waiting · api")

    try state.record(event(#"{"v":1,"source":"claude","activity":"finished","session":"s2"}"#))
    #expect(state.sessions[1] == AgentActivity(source: .claude, activity: .finished, project: "api", session: "s2"))
    #expect(state.agents.last?.session == "s1")

    try state.record(event(#"{"v":1,"source":"claude","activity":"finished","session":"s1","ended":true}"#))
    #expect(state.sessions.map(\.session) == ["s2", "c1"])
    try state.record(event(#"{"v":1,"source":"claude","activity":"finished","session":"s2","ended":true}"#))
    #expect(state.sessions.map(\.session) == ["c1"])
    // With every session closed, the agent shows what it last did.
    #expect(state.agents.last == AgentActivity(source: .claude, activity: .finished, project: "api"))
}

@MainActor
@Test func subagentsFollowTheirSessionAndLeaveWhenTheyStop() throws {
    let state = ActivityState()
    try state.record(event(#"{"v":1,"source":"claude","activity":"thinking","project":"amora-ai","session":"s1"}"#))
    try state.record(event(#"{"v":1,"source":"claude","activity":"thinking","project":"api","session":"s2"}"#))
    try state.record(event(#"{"v":1,"source":"claude","activity":"working","session":"s1","subagent":"a1","subagentType":"Explore"}"#))
    try state.record(event(#"{"v":1,"source":"claude","activity":"working","session":"s1","subagent":"a2","subagentType":"Plan"}"#))
    try state.record(event(#"{"v":1,"source":"claude","activity":"waiting","session":"s1","subagent":"a1"}"#))
    #expect(state.sessions.map(\.id) == ["claude|s1|", "claude|s1|a1", "claude|s1|a2", "claude|s2|"])
    let explore = state.sessions[1]
    #expect(explore.activity == .waiting)
    #expect(explore.project == "amora-ai")
    #expect(explore.subagentType == "Explore")
    #expect(explore.title == "Claude Code › Explore")
    #expect(explore.tag == "Explore")
    #expect(state.agents.first?.id == "claude|s1|a1")
    #expect(activitySummary([explore]) == "Claude Code › Explore: Waiting · amora-ai")

    try state.record(event(#"{"v":1,"source":"claude","activity":"finished","session":"s1","subagent":"a1","ended":true}"#))
    #expect(state.sessions.map(\.id) == ["claude|s1|", "claude|s1|a2", "claude|s2|"])
    try state.record(event(#"{"v":1,"source":"claude","activity":"finished","session":"s1","ended":true}"#))
    #expect(state.sessions.map(\.id) == ["claude|s2|"])
}

@MainActor
@Test func aSubagentFromAnUnseenSessionBringsItsSession() throws {
    let state = ActivityState()
    try state.record(event(#"{"v":1,"source":"codex","activity":"working","project":"api","session":"s9","subagent":"t1","subagentType":"worker"}"#))
    #expect(state.sessions == [
        AgentActivity(source: .codex, activity: .working, project: "api", session: "s9"),
        AgentActivity(source: .codex, activity: .working, project: "api", session: "s9", subagent: "t1", subagentType: "worker")
    ])
}

@MainActor
@Test func hooksFromAnEarlierAmoraGiveWayToSessions() throws {
    let state = ActivityState()
    try state.record(event(#"{"v":1,"source":"cursor","activity":"working","project":"site"}"#))
    try state.record(event(#"{"v":1,"source":"claude","activity":"working","project":"amora-ai"}"#))
    #expect(state.sessions.map(\.id) == ["cursor||", "claude||"])
    try state.record(event(#"{"v":1,"source":"claude","activity":"thinking","project":"amora-ai","session":"s1"}"#))
    #expect(state.sessions.map(\.id) == ["cursor||", "claude|s1|"])
}

@MainActor
@Test func dropsSessionsThatStopReporting() throws {
    let state = ActivityState()
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    try state.record(event(#"{"v":1,"source":"claude","activity":"finished","session":"quiet"}"#), at: start)
    try state.record(event(#"{"v":1,"source":"claude","activity":"waiting","session":"asking"}"#), at: start)
    try state.record(event(#"{"v":1,"source":"codex","activity":"working","session":"busy"}"#), at: start)
    try state.record(event(#"{"v":1,"source":"codex","activity":"working","session":"busy","subagent":"t1"}"#), at: start)
    let later = start.addingTimeInterval(ActivityState.sessionTimeout - 60)
    try state.record(event(#"{"v":1,"source":"codex","activity":"working","session":"busy","subagent":"t1"}"#), at: later)

    state.removeStaleSessions(now: start.addingTimeInterval(ActivityState.sessionTimeout - 1))
    #expect(state.sessions.count == 4)
    state.removeStaleSessions(now: start.addingTimeInterval(ActivityState.sessionTimeout + 1))
    // A subagent that keeps reporting keeps its session open too.
    #expect(state.sessions.map(\.id) == ["claude|asking|", "codex|busy|", "codex|busy|t1"])
    state.removeStaleSessions(now: later.addingTimeInterval(ActivityState.sessionTimeout + 1))
    #expect(state.sessions.map(\.id) == ["claude|asking|"])
    state.removeStaleSessions(now: start.addingTimeInterval(ActivityState.waitingSessionTimeout + 1))
    #expect(state.sessions.isEmpty)
    #expect(state.agents.map(\.activity) == [.waiting, .working])
}
