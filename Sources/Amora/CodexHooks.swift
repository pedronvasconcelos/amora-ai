import Foundation

struct CodexHooks {
    enum ConfigurationError: LocalizedError {
        case invalidConfiguration
        case missingScript

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                "Codex hooks.json has an unsupported structure. Your configuration was not changed."
            case .missingScript:
                "The bundled Codex hook could not be found."
            }
        }
    }

    private let configurationURL: URL
    private let scriptURL: URL
    private let events = ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop"]

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let codexDirectory = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appending(path: ".codex", directoryHint: .isDirectory)
        configurationURL = codexDirectory.appending(path: "hooks.json")
        scriptURL = home.appending(path: "Library/Application Support/Amora/hooks/codex-hook.sh")
    }

    func install() throws {
        var document = try readConfiguration()
        var hooks = try removingOwnedHooks(from: document)
        guard let bundledScript = Bundle.module.url(forResource: "codex-hook", withExtension: "sh") else {
            throw ConfigurationError.missingScript
        }
        let script = try Data(contentsOf: bundledScript)
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [[
                "type": "command",
                "command": command(for: event),
                "async": true,
                "timeout": 2
            ]]])
            hooks[event] = groups
        }
        document["hooks"] = hooks
        try writeConfiguration(document)
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return }
        var document = try readConfiguration()
        document["hooks"] = try removingOwnedHooks(from: document)
        try writeConfiguration(document)
    }

    private func command(for event: String) -> String {
        let quotedPath = "'" + scriptURL.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        return "/bin/sh \(quotedPath) \(event)"
    }

    private func readConfiguration() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return [:] }
        let data = try Data(contentsOf: configurationURL)
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigurationError.invalidConfiguration
        }
        return document
    }

    private func removingOwnedHooks(from document: [String: Any]) throws -> [String: Any] {
        guard document["hooks"] != nil else { return [:] }
        guard var hooks = document["hooks"] as? [String: Any] else {
            throw ConfigurationError.invalidConfiguration
        }
        for event in events {
            guard let value = hooks[event] else { continue }
            guard let groups = value as? [[String: Any]] else {
                throw ConfigurationError.invalidConfiguration
            }
            var remaining: [[String: Any]] = []
            for var group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    throw ConfigurationError.invalidConfiguration
                }
                let kept = handlers.filter {
                    !($0["type"] as? String == "command" && $0["command"] as? String == command(for: event))
                }
                if kept.count == handlers.count {
                    remaining.append(group)
                } else if !kept.isEmpty {
                    group["hooks"] = kept
                    remaining.append(group)
                }
            }
            if remaining.isEmpty && !groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = remaining
            }
        }
        return hooks
    }

    private func writeConfiguration(_ document: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configurationURL, options: .atomic)
    }
}
