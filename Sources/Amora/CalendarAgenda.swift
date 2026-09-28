import AppKit
import EventKit
import Foundation

enum CalendarAccess: Equatable {
    case notDetermined
    case granted
    case denied
}

struct AgendaCalendar: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
}

struct AgendaAccount: Identifiable, Equatable {
    let name: String
    let calendars: [AgendaCalendar]

    var id: String { name }
}

struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let account: String
}

/// Calendars grouped by the account that owns them, so each Google account added to macOS appears once.
func agendaAccounts(_ calendars: [AgendaCalendar]) -> [AgendaAccount] {
    Dictionary(grouping: calendars, by: \.account)
        .map { name, calendars in
            AgendaAccount(
                name: name,
                calendars: calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// Events that have not ended, from visible calendars, soonest first. All-day events lead their day.
func upcomingAgenda(_ events: [AgendaEvent], hidden: Set<String>, now: Date, limit: Int) -> [AgendaEvent] {
    Array(
        events
            .filter { $0.end > now && !hidden.contains($0.calendarID) }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
    )
}

enum AgendaReminder {
    static let lead: TimeInterval = 10 * 60
    static let grace: TimeInterval = 5 * 60
}

/// The timed event the pet should announce: one starting within `lead`, or that started less than `grace` ago.
func imminentEvent(
    _ events: [AgendaEvent],
    now: Date,
    lead: TimeInterval = AgendaReminder.lead,
    grace: TimeInterval = AgendaReminder.grace
) -> AgendaEvent? {
    events
        .filter { !$0.isAllDay && $0.start <= now.addingTimeInterval(lead) && $0.start > now.addingTimeInterval(-grace) }
        .min { $0.start < $1.start }
}

func agendaCountdown(_ event: AgendaEvent, now: Date) -> String {
    let seconds = event.start.timeIntervalSince(now)
    guard seconds > 0 else { return "now" }
    return "\(Int((seconds / 60).rounded(.up)))m"
}

func agendaTimeLabel(
    _ event: AgendaEvent,
    now: Date,
    calendar: Calendar = .current,
    locale: Locale = .current
) -> String {
    let tomorrow = !calendar.isDate(event.start, inSameDayAs: now) && event.start > now
    if event.isAllDay {
        return tomorrow ? "Tomorrow, all day" : "All day"
    }
    if event.start <= now {
        return "Now"
    }
    let seconds = event.start.timeIntervalSince(now)
    if seconds < 60 * 60 {
        return "In \(Int((seconds / 60).rounded(.up))) min"
    }
    var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
    style.timeZone = calendar.timeZone
    let time = event.start.formatted(style)
    return tomorrow ? "Tomorrow \(time)" : time
}

func agendaReminderDescription(_ event: AgendaEvent, now: Date) -> String {
    let seconds = event.start.timeIntervalSince(now)
    guard seconds > 0 else { return "\(event.title) is starting" }
    return "\(event.title) in \(Int((seconds / 60).rounded(.up))) min"
}

struct CalendarStore {
    var access: () -> CalendarAccess
    var requestAccess: (@escaping @MainActor @Sendable (CalendarAccess) -> Void) -> Void
    var calendars: () -> [AgendaCalendar]
    var events: (Date, Date) -> [AgendaEvent]

    @MainActor static let eventKit: CalendarStore = {
        let store = EKEventStore()
        func currentAccess() -> CalendarAccess {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .granted
            case .notDetermined: .notDetermined
            default: .denied
            }
        }
        return CalendarStore(
            access: currentAccess,
            requestAccess: { done in
                store.requestFullAccessToEvents { _, _ in
                    Task { @MainActor in done(currentAccess()) }
                }
            },
            calendars: {
                store.calendars(for: .event).map { calendar in
                    AgendaCalendar(
                        id: calendar.calendarIdentifier,
                        title: calendar.title,
                        account: calendar.source?.title ?? "Other"
                    )
                }
            },
            events: { start, end in
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
                return store.events(matching: predicate).compactMap { event in
                    guard event.status != .canceled,
                          event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined,
                          let calendar = event.calendar
                    else { return nil }
                    let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return AgendaEvent(
                        id: "\(event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)",
                        title: title.isEmpty ? "Untitled event" : title,
                        start: event.startDate,
                        end: event.endDate,
                        isAllDay: event.isAllDay,
                        calendarID: calendar.calendarIdentifier,
                        calendarTitle: calendar.title,
                        account: calendar.source?.title ?? "Other"
                    )
                }
            }
        )
    }()
}

@MainActor
final class CalendarAgenda: ObservableObject {
    static let hiddenCalendarsKey = "calendarHiddenIDs"
    static let menuLimit = 6
    static let refreshInterval: TimeInterval = 30

    @Published private(set) var access: CalendarAccess
    @Published private(set) var accounts: [AgendaAccount] = []
    @Published private(set) var upcoming: [AgendaEvent] = []
    @Published private(set) var imminent: AgendaEvent?
    @Published private(set) var hiddenCalendarIDs: Set<String>
    @Published private(set) var now: Date

    private let store: CalendarStore
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let calendar: Calendar
    private var events: [AgendaEvent] = []
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?

    init(
        store: CalendarStore = .eventKit,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        clock: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.defaults = defaults
        self.calendar = calendar
        self.clock = clock
        access = store.access()
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Self.hiddenCalendarsKey) ?? [])
        now = clock()
        refresh()
    }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        changeObserver = nil
    }

    func requestAccess() {
        guard access == .notDetermined else { return }
        store.requestAccess { [weak self] access in
            self?.access = access
            self?.refresh()
        }
    }

    func refresh() {
        access = store.access()
        now = clock()
        guard access == .granted else {
            accounts = []
            events = []
            upcoming = []
            imminent = nil
            return
        }
        accounts = agendaAccounts(store.calendars())
        let startOfToday = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now.addingTimeInterval(48 * 60 * 60)
        events = store.events(startOfToday, end)
        applyVisibility()
    }

    func isVisible(_ calendarID: String) -> Bool {
        !hiddenCalendarIDs.contains(calendarID)
    }

    func setVisible(_ visible: Bool, calendarID: String) {
        if visible {
            hiddenCalendarIDs.remove(calendarID)
        } else {
            hiddenCalendarIDs.insert(calendarID)
        }
        defaults.set(hiddenCalendarIDs.sorted(), forKey: Self.hiddenCalendarsKey)
        applyVisibility()
    }

    func timeLabel(for event: AgendaEvent) -> String {
        agendaTimeLabel(event, now: now, calendar: calendar)
    }

    func openInternetAccounts() {
        open("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
    }

    func openPrivacySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }

    private func applyVisibility() {
        upcoming = upcomingAgenda(events, hidden: hiddenCalendarIDs, now: now, limit: Self.menuLimit)
        imminent = imminentEvent(events.filter { isVisible($0.calendarID) }, now: now)
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
