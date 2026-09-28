import Foundation
import Testing
@testable import Amora

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let noon = Date(timeIntervalSince1970: 1_789_992_000)

private func event(
    _ title: String,
    startsIn minutes: Double,
    lasting duration: Double = 30,
    allDay: Bool = false,
    calendarID: String = "work",
    account: String = "pedro@gmail.com"
) -> AgendaEvent {
    let start = noon.addingTimeInterval(minutes * 60)
    return AgendaEvent(
        id: "\(title)-\(minutes)",
        title: title,
        start: start,
        end: start.addingTimeInterval(duration * 60),
        isAllDay: allDay,
        calendarID: calendarID,
        calendarTitle: calendarID.capitalized,
        account: account
    )
}

@Test func groupsCalendarsByAccount() {
    let accounts = agendaAccounts([
        AgendaCalendar(id: "3", title: "Work", account: "pedro@company.com"),
        AgendaCalendar(id: "1", title: "Personal", account: "pedro@gmail.com"),
        AgendaCalendar(id: "2", title: "Birthdays", account: "pedro@gmail.com")
    ])
    #expect(accounts.map(\.name) == ["pedro@company.com", "pedro@gmail.com"])
    #expect(accounts[1].calendars.map(\.title) == ["Birthdays", "Personal"])
}

@Test func upcomingAgendaSkipsEndedAndHiddenEventsAndSortsBySoonest() {
    let events = [
        event("Later", startsIn: 120),
        event("Ended", startsIn: -60, lasting: 30),
        event("In progress", startsIn: -10, lasting: 30),
        event("Hidden", startsIn: 5, calendarID: "family"),
        event("Soon", startsIn: 5)
    ]
    let upcoming = upcomingAgenda(events, hidden: ["family"], now: noon, limit: 2)
    #expect(upcoming.map(\.title) == ["In progress", "Soon"])
}

@Test func imminentEventCoversTheLeadAndGraceWindow() {
    #expect(imminentEvent([event("Far", startsIn: 11)], now: noon) == nil)
    #expect(imminentEvent([event("Standup", startsIn: 10)], now: noon)?.title == "Standup")
    #expect(imminentEvent([event("Started", startsIn: -4)], now: noon)?.title == "Started")
    #expect(imminentEvent([event("Old", startsIn: -5)], now: noon) == nil)
    #expect(imminentEvent([event("Holiday", startsIn: 1, allDay: true)], now: noon) == nil)
    #expect(imminentEvent([event("B", startsIn: 8), event("A", startsIn: 3)], now: noon)?.title == "A")
}

@Test func describesWhenEachEventStarts() {
    let locale = Locale(identifier: "en_US_POSIX")
    #expect(agendaTimeLabel(event("Now", startsIn: -1), now: noon, calendar: utc, locale: locale) == "Now")
    #expect(agendaTimeLabel(event("Soon", startsIn: 4.5), now: noon, calendar: utc, locale: locale) == "In 5 min")
    #expect(agendaTimeLabel(event("Later", startsIn: 150), now: noon, calendar: utc, locale: locale) == "2:30\u{202F}PM")
    #expect(agendaTimeLabel(event("Tomorrow", startsIn: 21 * 60), now: noon, calendar: utc, locale: locale) == "Tomorrow 9:00\u{202F}AM")
    #expect(agendaTimeLabel(event("Today", startsIn: -12 * 60, lasting: 24 * 60, allDay: true), now: noon, calendar: utc, locale: locale) == "All day")
    #expect(agendaTimeLabel(event("Next", startsIn: 12 * 60, lasting: 24 * 60, allDay: true), now: noon, calendar: utc, locale: locale) == "Tomorrow, all day")

    #expect(agendaCountdown(event("Soon", startsIn: 4.2), now: noon) == "5m")
    #expect(agendaCountdown(event("Started", startsIn: -1), now: noon) == "now")
    #expect(agendaReminderDescription(event("Standup", startsIn: 3), now: noon) == "Standup in 3 min")
    #expect(agendaReminderDescription(event("Standup", startsIn: 0), now: noon) == "Standup is starting")
}

@MainActor
@Test func agendaReadsEveryAccountAndRemembersHiddenCalendars() throws {
    let suite = "amora.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fake = FakeCalendarStore(access: .notDetermined)
    fake.calendars = [
        AgendaCalendar(id: "work", title: "Work", account: "pedro@company.com"),
        AgendaCalendar(id: "family", title: "Family", account: "pedro@gmail.com")
    ]
    fake.events = [
        event("Standup", startsIn: 5, account: "pedro@company.com"),
        event("Dinner", startsIn: 400, calendarID: "family")
    ]
    let agenda = CalendarAgenda(store: fake.store, defaults: defaults, calendar: utc, clock: { noon })
    #expect(agenda.access == .notDetermined)
    #expect(agenda.upcoming.isEmpty)
    #expect(fake.requestedRange == nil)

    fake.access = .granted
    agenda.requestAccess()
    #expect(agenda.access == .granted)
    #expect(agenda.accounts.map(\.name) == ["pedro@company.com", "pedro@gmail.com"])
    #expect(agenda.upcoming.map(\.title) == ["Standup", "Dinner"])
    #expect(agenda.imminent?.title == "Standup")
    let range = try #require(fake.requestedRange)
    #expect(range.0 == utc.startOfDay(for: noon))
    #expect(range.1.timeIntervalSince(range.0) == 2 * 86_400)

    agenda.setVisible(false, calendarID: "work")
    #expect(agenda.upcoming.map(\.title) == ["Dinner"])
    #expect(agenda.imminent == nil)

    let restored = CalendarAgenda(store: fake.store, defaults: defaults, calendar: utc, clock: { noon })
    #expect(restored.isVisible("work") == false)
    #expect(restored.isVisible("family"))
    restored.setVisible(true, calendarID: "work")
    #expect(restored.imminent?.title == "Standup")
}

@MainActor
@Test func agendaClearsEventsWhenAccessIsRevoked() {
    let fake = FakeCalendarStore(access: .granted)
    fake.calendars = [AgendaCalendar(id: "work", title: "Work", account: "pedro@gmail.com")]
    fake.events = [event("Standup", startsIn: 5)]
    let agenda = CalendarAgenda(store: fake.store, defaults: UserDefaults(suiteName: UUID().uuidString)!, calendar: utc, clock: { noon })
    #expect(agenda.upcoming.count == 1)
    fake.access = .denied
    agenda.refresh()
    #expect(agenda.access == .denied)
    #expect(agenda.accounts.isEmpty)
    #expect(agenda.upcoming.isEmpty)
    #expect(agenda.imminent == nil)
}

@Test func imminentEventMakesThePetWaveUnlessAnAgentIsWaiting() {
    #expect(petPose(for: nil, hasImminentEvent: true) == .reminding)
    #expect(petPose(for: .working, hasImminentEvent: true) == .reminding)
    #expect(petPose(for: .waiting, hasImminentEvent: true) == .waiting)
    #expect(petPose(for: .working, hasImminentEvent: false) == .working)
    #expect(petAnimation(for: .reminding) == .waving)
    #expect(petAccessibilityLabel(for: [], reminder: "Standup in 3 min") == "Amora; Standup in 3 min")
    #expect(petAccessibilityLabel(
        for: [AgentActivity(source: .cursor, activity: .working)],
        reminder: "Standup is starting"
    ) == "Cursor, working; Standup is starting")
}

@MainActor
final class FakeCalendarStore {
    var access: CalendarAccess
    var calendars: [AgendaCalendar] = []
    var events: [AgendaEvent] = []
    var requestedRange: (Date, Date)?

    init(access: CalendarAccess) {
        self.access = access
    }

    var store: CalendarStore {
        CalendarStore(
            access: { self.access },
            requestAccess: { done in done(self.access) },
            calendars: { self.calendars },
            events: { start, end in
                self.requestedRange = (start, end)
                return self.events.filter { $0.start < end && $0.end > start }
            }
        )
    }
}

@MainActor
func emptyAgenda() -> CalendarAgenda {
    CalendarAgenda(
        store: FakeCalendarStore(access: .notDetermined).store,
        defaults: UserDefaults(suiteName: "amora.tests.\(UUID().uuidString)")!
    )
}
