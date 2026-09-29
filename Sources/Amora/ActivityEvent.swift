import Foundation

struct ActivityEvent: Decodable {
    enum Source: String, Decodable, CaseIterable {
        case cursor
        case claude
        case codex

        var displayName: String {
            switch self {
            case .cursor: "Cursor"
            case .claude: "Claude Code"
            case .codex: "Codex"
            }
        }

        var monogram: String {
            switch self {
            case .cursor: "CR"
            case .claude: "CC"
            case .codex: "CX"
            }
        }
    }

    enum Activity: String, Decodable {
        case thinking
        case working
        case waiting
        case finished

        var label: String { rawValue.capitalized }

        var symbolName: String {
            switch self {
            case .thinking: "ellipsis"
            case .working: "hammer.fill"
            case .waiting: "hand.raised.fill"
            case .finished: "checkmark"
            }
        }

        var urgency: Int {
            switch self {
            case .waiting: 3
            case .working: 2
            case .thinking: 1
            case .finished: 0
            }
        }
    }

    let v: Int
    let source: Source
    let activity: Activity
    let project: String?
    /// The agent's own id for the session, so two sessions of one agent stay apart.
    let session: String?
    /// Set when a subagent inside the session reported, rather than the session itself.
    let subagent: String?
    let subagentType: String?
    /// The session, or the subagent, has closed.
    let ended: Bool

    private enum CodingKeys: String, CodingKey {
        case v, source, activity, project, session, subagent, subagentType, ended
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        source = try container.decode(Source.self, forKey: .source)
        activity = try container.decode(Activity.self, forKey: .activity)
        let decodedProject: String?
        if let raw = try? container.decodeIfPresent(String.self, forKey: .project) {
            decodedProject = raw
        } else {
            decodedProject = nil
        }
        project = acceptedProjectName(decodedProject)
        session = acceptedIdentifier(try? container.decodeIfPresent(String.self, forKey: .session))
        subagent = acceptedIdentifier(try? container.decodeIfPresent(String.self, forKey: .subagent))
        subagentType = subagent == nil
            ? nil
            : acceptedProjectName(try? container.decodeIfPresent(String.self, forKey: .subagentType))
        ended = (try? container.decodeIfPresent(Bool.self, forKey: .ended)) ?? false
    }

    static func decode(_ data: Data) -> ActivityEvent? {
        guard let event = try? JSONDecoder().decode(Self.self, from: data), event.v == 1 else {
            return nil
        }
        return event
    }
}

/// A single folder name safe to show in the menu. Full paths and control characters are dropped.
func acceptedProjectName(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...120).contains(name.count), name != ".", name != ".." else { return nil }
    guard !name.contains("/"), !name.contains("\\"), !name.contains("\"") else { return nil }
    guard name.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else { return nil }
    return name
}

/// An opaque session or subagent id. Anything that could be more than an id is dropped.
func acceptedIdentifier(_ raw: String?) -> String? {
    guard let raw, (1...128).contains(raw.unicodeScalars.count) else { return nil }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
    guard raw.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
    return raw
}

struct AgentSnapshot: Equatable {
    var activity: ActivityEvent.Activity
    var project: String?
}

/// What one agent, one of its sessions, or one subagent in a session is doing.
struct AgentActivity: Equatable, Identifiable {
    let source: ActivityEvent.Source
    var activity: ActivityEvent.Activity
    var project: String? = nil
    var session: String? = nil
    var subagent: String? = nil
    var subagentType: String? = nil

    var id: String { Self.id(source: source, session: session, subagent: subagent) }
    var isSubagent: Bool { subagent != nil }

    /// "Claude Code", or "Claude Code › Explore" for a subagent.
    var title: String {
        guard isSubagent else { return source.displayName }
        return "\(source.displayName) › \(subagentType ?? "Subagent")"
    }

    /// The short name on a session's pet: the subagent's type, or the project.
    var tag: String? {
        isSubagent ? (subagentType ?? "Subagent") : project
    }

    static func id(source: ActivityEvent.Source, session: String?, subagent: String?) -> String {
        [source.rawValue, session ?? "", subagent ?? ""].joined(separator: "|")
    }
}

/// One entry per agent: its session that most needs attention, or what it last reported when no session is open.
func agentActivities(
    sessions: [AgentActivity],
    activities: [ActivityEvent.Source: AgentSnapshot]
) -> [AgentActivity] {
    ActivityEvent.Source.allCases.compactMap { source in
        leadingActivity(sessions.filter { $0.source == source })
            ?? activities[source].map { AgentActivity(source: source, activity: $0.activity, project: $0.project) }
    }
}

/// Every open session and subagent, grouped by agent. An agent with none open shows what it last reported.
func activityRows(
    sessions: [AgentActivity],
    activities: [ActivityEvent.Source: AgentSnapshot]
) -> [AgentActivity] {
    ActivityEvent.Source.allCases.flatMap { source -> [AgentActivity] in
        let open = sessions.filter { $0.source == source }
        if !open.isEmpty { return open }
        return activities[source].map { [AgentActivity(source: source, activity: $0.activity, project: $0.project)] } ?? []
    }
}

/// The agent the pet should mirror: the one that most needs attention, ties broken by agent order.
func leadingActivity(_ agents: [AgentActivity]) -> AgentActivity? {
    agents.enumerated().max { lhs, rhs in
        if lhs.element.activity.urgency != rhs.element.activity.urgency {
            return lhs.element.activity.urgency < rhs.element.activity.urgency
        }
        return lhs.offset > rhs.offset
    }?.element
}

func activitySummary(_ agents: [AgentActivity]) -> String? {
    guard !agents.isEmpty else { return nil }
    return agents.map { agent in
        if let project = agent.project {
            return "\(agent.title): \(agent.activity.label) · \(project)"
        }
        return "\(agent.title): \(agent.activity.label)"
    }.joined(separator: "\n")
}
