import Foundation

@MainActor
final class SettingsModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let installed: Bool
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError = false
    let launchAtLoginRegistersNow: Bool

    private let codex: CodexHooks
    private let cursor: CursorHooks
    private let claude: ClaudeHooks
    private let launchAtLogin: LaunchAtLogin

    init(
        codex: CodexHooks = CodexHooks(),
        cursor: CursorHooks = CursorHooks(),
        claude: ClaudeHooks = ClaudeHooks(),
        launchAtLogin: LaunchAtLogin = LaunchAtLogin()
    ) {
        self.codex = codex
        self.cursor = cursor
        self.claude = claude
        self.launchAtLogin = launchAtLogin
        launchAtLoginEnabled = launchAtLogin.isEnabled
        launchAtLoginRegistersNow = launchAtLogin.registersWithSystem
        refresh()
    }

    func refresh() {
        var readError: String?
        rows = [
            statusRow(id: "codex", name: "Codex", read: { try codex.isInstalled() }, readError: &readError),
            statusRow(id: "cursor", name: "Cursor", read: { try cursor.isInstalled() }, readError: &readError),
            statusRow(id: "claude", name: "Claude Code", read: { try claude.isInstalled() }, readError: &readError)
        ]
        launchAtLoginEnabled = launchAtLogin.isEnabled
        if let readError {
            statusIsError = true
            statusMessage = readError
        }
    }

    func setInstalled(_ installed: Bool, for id: String) {
        do {
            switch (id, installed) {
            case ("codex", true): try codex.install()
            case ("codex", false): try codex.remove()
            case ("cursor", true): try cursor.install()
            case ("cursor", false): try cursor.remove()
            case ("claude", true): try claude.install()
            case ("claude", false): try claude.remove()
            default: return
            }
            refresh()
            statusIsError = false
            statusMessage = confirmation(installed: installed, id: id)
        } catch {
            refresh()
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLogin.isEnabled
            statusIsError = false
            statusMessage = enabled
                ? (launchAtLoginRegistersNow
                    ? "Amora will open when you log in."
                    : "Saved. Amora will open at login once it is installed as an app.")
                : "Amora will no longer open when you log in."
        } catch {
            launchAtLoginEnabled = launchAtLogin.isEnabled
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    func applyStoredLaunchAtLogin() {
        guard launchAtLogin.isEnabled, launchAtLogin.registersWithSystem else { return }
        do {
            try launchAtLogin.setEnabled(true)
            launchAtLoginEnabled = true
        } catch {
            launchAtLoginEnabled = launchAtLogin.isEnabled
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    private func statusRow(
        id: String,
        name: String,
        read: () throws -> Bool,
        readError: inout String?
    ) -> Row {
        do {
            return Row(id: id, name: name, installed: try read())
        } catch {
            if readError == nil {
                readError = error.localizedDescription
            }
            return Row(id: id, name: name, installed: false)
        }
    }

    private func confirmation(installed: Bool, id: String) -> String {
        if !installed {
            switch id {
            case "codex": return "Amora's Codex hooks were removed."
            case "cursor": return "Amora's Cursor hooks were removed."
            default: return "Amora's Claude Code hooks were removed."
            }
        }
        switch id {
        case "codex":
            return "Installed. Review and trust Amora's hooks in Codex Hooks settings or /hooks in the CLI."
        case "cursor":
            return "Installed. Review and trust Amora's hooks in Cursor Hooks settings."
        default:
            return "Installed. Review and trust Amora's hooks in Claude Code settings."
        }
    }
}
