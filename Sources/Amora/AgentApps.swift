import AppKit
import Foundation

enum AgentAppKind: String, CaseIterable, Identifiable, Equatable {
    case cursor
    case claude
    case codex

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cursor: "Cursor"
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }
}

enum AgentAppState: Equatable {
    case notInstalled
    case notRunning
    case running

    var label: String {
        switch self {
        case .notInstalled: "Not installed"
        case .notRunning: "Not running"
        case .running: "Running"
        }
    }
}

struct AgentAppListing: Identifiable, Equatable {
    let kind: AgentAppKind
    let state: AgentAppState

    var id: String { kind.id }
    var name: String { kind.name }
}

func agentAppState(installed: Bool, running: Bool) -> AgentAppState {
    if running { return .running }
    if installed { return .notRunning }
    return .notInstalled
}

func agentAppListings(installed: Set<String>, running: Set<String>) -> [AgentAppListing] {
    AgentAppKind.allCases.map { kind in
        AgentAppListing(
            kind: kind,
            state: agentAppState(
                installed: installed.contains(kind.bundleIdentifier),
                running: running.contains(kind.bundleIdentifier)
            )
        )
    }
}

struct AgentAppLookup {
    var installed: () -> Set<String>
    var running: () -> Set<String>
    var icon: (String) -> NSImage?
    var open: (String) -> Void
    var close: (String) -> Void

    @MainActor static let workspace = AgentAppLookup(
        installed: {
            Set(AgentAppKind.allCases.compactMap { kind in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: kind.bundleIdentifier) == nil
                    ? nil
                    : kind.bundleIdentifier
            })
        },
        running: {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        icon: { bundleIdentifier in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return nil
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        },
        open: { bundleIdentifier in
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                app.activate(options: [.activateAllWindows])
                return
            }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        },
        close: { bundleIdentifier in
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                app.terminate()
            }
        }
    )
}

@MainActor
final class AgentApps: NSObject, ObservableObject {
    @Published private(set) var listings: [AgentAppListing] = []
    private let lookup: AgentAppLookup
    private nonisolated(unsafe) var observationCenter: NotificationCenter?

    init(lookup: AgentAppLookup = .workspace) {
        self.lookup = lookup
        super.init()
        refresh()
        startObserving()
    }

    deinit {
        observationCenter?.removeObserver(self)
    }

    func refresh() {
        listings = agentAppListings(installed: lookup.installed(), running: lookup.running())
    }

    func icon(for kind: AgentAppKind) -> NSImage? {
        lookup.icon(kind.bundleIdentifier)
    }

    func open(_ kind: AgentAppKind) {
        guard let state = listings.first(where: { $0.kind == kind })?.state, state != .notInstalled else {
            return
        }
        lookup.open(kind.bundleIdentifier)
    }

    func close(_ kind: AgentAppKind) {
        guard listings.first(where: { $0.kind == kind })?.state == .running else { return }
        lookup.close(kind.bundleIdentifier)
    }

    private func startObserving() {
        guard observationCenter == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        observationCenter = center
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationsChanged(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationsChanged(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func workspaceApplicationsChanged(_ notification: Notification) {
        refresh()
    }
}

enum MenuAnchor: Equatable {
    case statusItem
    case pet(UUID)
}

enum MenuToggle: Equatable {
    case close
    case show(MenuAnchor)
}

func menuToggle(isShown: Bool, current: MenuAnchor?, requested: MenuAnchor) -> MenuToggle {
    if isShown, current == requested {
        return .close
    }
    return .show(requested)
}
