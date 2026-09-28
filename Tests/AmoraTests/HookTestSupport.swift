import Darwin
import Foundation
import Testing

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
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    input.fileHandleForWriting.write(Data(payload.utf8))
    try input.fileHandleForWriting.close()
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
