import Foundation
import Testing
@testable import Amora

@MainActor
@Test func settingsShowsInstallStateForEachIntegration() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let codex = CodexHooks(home: home, environment: [:])
    let cursor = CursorHooks(home: home)
    let claude = ClaudeHooks(home: home, environment: [:])
    let (model, suite) = try settingsModel(home: home, codex: codex, cursor: cursor, claude: claude)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    #expect(model.rows.map(\.id) == ["codex", "cursor", "claude"])
    #expect(model.rows.map(\.installed) == [false, false, false])

    model.setInstalled(true, for: "codex")
    #expect(try codex.isInstalled())
    #expect(model.rows.first { $0.id == "codex" }?.installed == true)
    #expect(model.statusIsError == false)
    #expect(model.statusMessage?.contains("Codex") == true)
    model.setInstalled(false, for: "codex")
    #expect(try codex.isInstalled() == false)
    #expect(model.rows.first { $0.id == "codex" }?.installed == false)

    model.setInstalled(true, for: "cursor")
    #expect(try cursor.isInstalled())
    #expect(model.rows.first { $0.id == "cursor" }?.installed == true)
    model.setInstalled(false, for: "cursor")
    #expect(try cursor.isInstalled() == false)

    model.setInstalled(true, for: "claude")
    #expect(try claude.isInstalled())
    #expect(model.rows.first { $0.id == "claude" }?.installed == true)
    model.setInstalled(false, for: "claude")
    #expect(try claude.isInstalled() == false)
    #expect(model.statusMessage?.contains("Claude Code") == true)
}

@MainActor
@Test func installedStatusRequiresEveryOwnedHook() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let codex = CodexHooks(home: home, environment: [:])
    try codex.install()
    try removeHookEvent("Stop", from: home.appending(path: ".codex/hooks.json"))
    #expect(try codex.isInstalled() == false)

    let cursor = CursorHooks(home: home)
    try cursor.install()
    try removeHookEvent("stop", from: home.appending(path: ".cursor/hooks.json"))
    #expect(try cursor.isInstalled() == false)

    let claude = ClaudeHooks(home: home, environment: [:])
    try claude.install()
    try removeHookEvent("Stop", from: home.appending(path: ".claude/settings.json"))
    #expect(try claude.isInstalled() == false)
}

@MainActor
@Test func settingsLeavesInvalidConfigurationUntouched() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let directory = home.appending(path: ".codex")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configuration = directory.appending(path: "hooks.json")
    let original = Data("[]".utf8)
    try original.write(to: configuration)
    let (model, suite) = try settingsModel(home: home)
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    #expect(model.statusIsError == true)
    #expect(model.rows.first { $0.id == "codex" }?.installed == false)
    #expect(try Data(contentsOf: configuration) == original)
    model.setInstalled(true, for: "codex")
    #expect(model.statusIsError == true)
    #expect(try Data(contentsOf: configuration) == original)
}

@MainActor
@Test func launchAtLoginPreferencePersistsWithoutABundledApp() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let suite = "amora.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var calls = 0
    let setting = LaunchAtLogin(defaults: defaults, registersWithSystem: false) { _ in calls += 1 }
    let (model, _) = try settingsModel(home: home, launchAtLogin: setting)
    #expect(model.launchAtLoginEnabled == false)
    #expect(model.launchAtLoginRegistersNow == false)
    model.setLaunchAtLogin(true)
    #expect(calls == 0)
    #expect(model.launchAtLoginEnabled == true)
    #expect(model.statusIsError == false)
    let (restored, _) = try settingsModel(
        home: home,
        launchAtLogin: LaunchAtLogin(defaults: defaults, registersWithSystem: false) { _ in }
    )
    #expect(restored.launchAtLoginEnabled == true)
    model.setLaunchAtLogin(false)
    #expect(calls == 0)
    #expect(model.launchAtLoginEnabled == false)
    restored.refresh()
    #expect(restored.launchAtLoginEnabled == false)
}

@MainActor
@Test func launchAtLoginKeepsThePreviousPreferenceWhenRegistrationFails() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let suite = "amora.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let setting = LaunchAtLogin(defaults: defaults, registersWithSystem: true) { _ in
        throw CocoaError(.fileWriteUnknown)
    }
    let (model, _) = try settingsModel(home: home, launchAtLogin: setting)
    model.setLaunchAtLogin(true)
    #expect(model.launchAtLoginEnabled == false)
    #expect(model.statusIsError == true)
    #expect(setting.isEnabled == false)
}

@MainActor
private func settingsModel(
    home: URL,
    codex: CodexHooks? = nil,
    cursor: CursorHooks? = nil,
    claude: ClaudeHooks? = nil,
    launchAtLogin: LaunchAtLogin? = nil,
    registersWithSystem: Bool = false
) throws -> (SettingsModel, String) {
    let setting: LaunchAtLogin
    let suite: String
    if let launchAtLogin {
        setting = launchAtLogin
        suite = ""
    } else {
        suite = "amora.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        setting = LaunchAtLogin(defaults: defaults, registersWithSystem: registersWithSystem) { _ in }
    }
    return (SettingsModel(
        codex: codex ?? CodexHooks(home: home, environment: [:]),
        cursor: cursor ?? CursorHooks(home: home),
        claude: claude ?? ClaudeHooks(home: home, environment: [:]),
        launchAtLogin: setting
    ), suite)
}

private func removeHookEvent(_ event: String, from url: URL) throws {
    var document = try readDocument(url)
    var hooks = try #require(document["hooks"] as? [String: Any])
    hooks.removeValue(forKey: event)
    document["hooks"] = hooks
    try JSONSerialization.data(withJSONObject: document).write(to: url)
}
