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

    static func decode(_ data: Data) -> ActivityEvent? {
        guard let event = try? JSONDecoder().decode(Self.self, from: data), event.v == 1 else {
            return nil
        }
        return event
    }
}

struct AgentActivity: Equatable, Identifiable {
    let source: ActivityEvent.Source
    let activity: ActivityEvent.Activity

    var id: ActivityEvent.Source { source }
}

func agentActivities(_ activities: [ActivityEvent.Source: ActivityEvent.Activity]) -> [AgentActivity] {
    ActivityEvent.Source.allCases.compactMap { source in
        activities[source].map { AgentActivity(source: source, activity: $0) }
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
    return agents.map { "\($0.source.displayName): \($0.activity.label)" }.joined(separator: "\n")
}
