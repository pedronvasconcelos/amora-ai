import Foundation
import Testing

func temporaryHome() throws -> URL {
    let home = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

func readDocument(_ url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

@MainActor
func runHook(_ command: String, home: URL) async throws -> String {
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
    input.fileHandleForWriting.write(Data(#"{"prompt":"private prompt","tool_input":"private contents"}"#.utf8))
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
