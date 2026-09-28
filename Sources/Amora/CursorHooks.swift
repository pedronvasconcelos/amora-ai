import Foundation

struct CursorHooks {
    enum ConfigurationError: LocalizedError {
        case invalidConfiguration
        case missingScript

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                "Cursor hooks.json has an unsupported structure. Your configuration was not changed."
            case .missingScript:
                "The bundled Cursor hook could not be found."
            }
        }
    }

    private let configurationURL: URL
    private let scriptURL: URL
    private let events = ["beforeSubmitPrompt", "preToolUse", "afterFileEdit", "stop"]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        configurationURL = home.appending(path: ".cursor/hooks.json")
        scriptURL = home.appending(path: "Library/Application Support/Amora/hooks/cursor-hook.sh")
    }

    func isInstalled() throws -> Bool {
        try containsOwnedHooks()
    }

    func install() throws {
        var document = try readConfiguration()
        try requireSupportedVersion(document)
        var hooks = try removingOwnedHooks(from: document)
        guard let bundledScript = Bundle.module.url(forResource: "cursor-hook", withExtension: "sh") else {
            throw ConfigurationError.missingScript
        }
        let script = try Data(contentsOf: bundledScript)
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        for event in events {
            var handlers = hooks[event] as? [[String: Any]] ?? []
            handlers.append([
                "command": command(for: event),
                "failClosed": false,
                "timeout": 2,
                "type": "command"
            ])
            hooks[event] = handlers
        }
        if document["version"] == nil {
            document["version"] = 1
        }
        document["hooks"] = hooks
        try writeConfiguration(document)
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return }
        var document = try readConfiguration()
        try requireSupportedVersion(document)
        document["hooks"] = try removingOwnedHooks(from: document)
        try writeConfiguration(document)
    }

    private func command(for event: String) -> String {
        let quotedPath = "'" + scriptURL.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        return "/bin/sh \(quotedPath) \(event)"
    }

    private func containsOwnedHooks() throws -> Bool {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return false }
        let document = try readConfiguration()
        try requireSupportedVersion(document)
        guard let hooksValue = document["hooks"] else { return false }
        guard let hooks = hooksValue as? [String: Any] else {
            throw ConfigurationError.invalidConfiguration
        }
        var installed = true
        for event in events {
            guard let value = hooks[event] else {
                installed = false
                continue
            }
            guard let handlers = value as? [[String: Any]] else {
                throw ConfigurationError.invalidConfiguration
            }
            if !handlers.contains(where: { $0["command"] as? String == command(for: event) }) {
                installed = false
            }
        }
        return installed
    }

    private func readConfiguration() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return [:] }
        let data = try Data(contentsOf: configurationURL)
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigurationError.invalidConfiguration
        }
        return document
    }

    private func requireSupportedVersion(_ document: [String: Any]) throws {
        guard let version = document["version"] else { return }
        guard CFGetTypeID(version as CFTypeRef) == CFNumberGetTypeID(),
              let number = version as? NSNumber,
              number.doubleValue == 1
        else {
            throw ConfigurationError.invalidConfiguration
        }
    }

    private func removingOwnedHooks(from document: [String: Any]) throws -> [String: Any] {
        guard document["hooks"] != nil else { return [:] }
        guard var hooks = document["hooks"] as? [String: Any] else {
            throw ConfigurationError.invalidConfiguration
        }
        for event in events {
            guard let value = hooks[event] else { continue }
            guard let handlers = value as? [[String: Any]] else {
                throw ConfigurationError.invalidConfiguration
            }
            let kept = handlers.filter { $0["command"] as? String != command(for: event) }
            if kept.count == handlers.count {
                hooks[event] = handlers
            } else if kept.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = kept
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
