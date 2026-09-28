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
