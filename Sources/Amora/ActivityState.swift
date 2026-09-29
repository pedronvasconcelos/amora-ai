import Foundation

@MainActor
final class ActivityState: ObservableObject {
    /// A session that has been quiet this long is dropped; its agent probably closed without saying so.
    static let sessionTimeout: TimeInterval = 30 * 60
    /// A session waiting on you stays longer, so its pet is still asking when you come back.
    static let waitingSessionTimeout: TimeInterval = 2 * 60 * 60

    /// What each agent last reported, shown when none of its sessions is open.
    @Published private(set) var activities: [ActivityEvent.Source: AgentSnapshot] = [:]
    /// Open sessions and subagents in the order they first reported. Each subagent follows its session.
    @Published private(set) var sessions: [AgentActivity] = []
    @Published var error: String?
    private var lastSeen: [String: Date] = [:]

    var agents: [AgentActivity] { agentActivities(sessions: sessions, activities: activities) }
    var rows: [AgentActivity] { activityRows(sessions: sessions, activities: activities) }

    func record(_ event: ActivityEvent, at now: Date = Date()) {
        let known = activities[event.source]
        if event.ended {
            end(event)
            return
        }
        activities[event.source] = AgentSnapshot(activity: event.activity, project: event.project ?? known?.project)

        var updated = sessions
        if event.session != nil {
            // Hooks from an earlier Amora sent no session id. Once the agent sends one, that entry is stale.
            let legacy = AgentActivity.id(source: event.source, session: nil, subagent: nil)
            updated.removeAll { $0.id == legacy }
            lastSeen[legacy] = nil
        }
        let sessionID = AgentActivity.id(source: event.source, session: event.session, subagent: nil)
        let id = AgentActivity.id(source: event.source, session: event.session, subagent: event.subagent)
        let parent = updated.first { $0.id == sessionID }
        if let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index].activity = event.activity
            updated[index].project = event.project ?? updated[index].project
            updated[index].subagentType = event.subagentType ?? updated[index].subagentType
        } else if event.subagent == nil {
            let fallback = event.session == nil ? known?.project : nil
            updated.append(AgentActivity(
                source: event.source,
                activity: event.activity,
                project: event.project ?? fallback,
                session: event.session
            ))
        } else {
            if parent == nil {
                // Amora started while the session was already running: its subagent is the first news of it.
                updated.append(AgentActivity(
                    source: event.source,
                    activity: .working,
                    project: event.project,
                    session: event.session
                ))
            }
            let entry = AgentActivity(
                source: event.source,
                activity: event.activity,
                project: event.project ?? parent?.project,
                session: event.session,
                subagent: event.subagent,
                subagentType: event.subagentType
            )
            let family = updated.lastIndex { $0.source == event.source && $0.session == event.session }
            updated.insert(entry, at: family.map { $0 + 1 } ?? updated.endIndex)
        }
        lastSeen[sessionID] = now
        lastSeen[id] = now
        sessions = updated
    }

    /// Drops sessions that stopped reporting without an end event, such as a closed terminal.
    func removeStaleSessions(now: Date = Date()) {
        let stale = Set(sessions.filter { entry in
            guard let seen = lastSeen[entry.id] else { return true }
            let timeout = entry.activity == .waiting ? Self.waitingSessionTimeout : Self.sessionTimeout
            return now.timeIntervalSince(seen) > timeout
        }.map(\.id))
        guard !stale.isEmpty else { return }
        let remaining = sessions.filter { entry in
            let sessionID = AgentActivity.id(source: entry.source, session: entry.session, subagent: nil)
            return !stale.contains(entry.id) && !stale.contains(sessionID)
        }
        for entry in sessions where !remaining.contains(where: { $0.id == entry.id }) {
            lastSeen[entry.id] = nil
        }
        sessions = remaining
    }

    private func end(_ event: ActivityEvent) {
        let id = AgentActivity.id(source: event.source, session: event.session, subagent: event.subagent)
        let removed: [AgentActivity]
        if event.subagent != nil {
            removed = sessions.filter { $0.id == id }
        } else {
            removed = sessions.filter { $0.source == event.source && $0.session == event.session }
            let project = event.project ?? sessions.first { $0.id == id }?.project ?? activities[event.source]?.project
            activities[event.source] = AgentSnapshot(activity: .finished, project: project)
        }
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        for id in ids { lastSeen[id] = nil }
        sessions.removeAll { ids.contains($0.id) }
    }
}
