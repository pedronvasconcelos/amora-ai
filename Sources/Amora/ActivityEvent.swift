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

    private enum CodingKeys: String, CodingKey {
        case v, source, activity, project
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

struct AgentSnapshot: Equatable {
    var activity: ActivityEvent.Activity
    var project: String?
}

struct AgentActivity: Equatable, Identifiable {
    let source: ActivityEvent.Source
    let activity: ActivityEvent.Activity
    var project: String? = nil

    var id: ActivityEvent.Source { source }
}

func agentActivities(_ activities: [ActivityEvent.Source: AgentSnapshot]) -> [AgentActivity] {
    ActivityEvent.Source.allCases.compactMap { source in
        activities[source].map {
            AgentActivity(source: source, activity: $0.activity, project: $0.project)
        }
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
            return "\(agent.source.displayName): \(agent.activity.label) · \(project)"
        }
        return "\(agent.source.displayName): \(agent.activity.label)"
    }.joined(separator: "\n")
}
