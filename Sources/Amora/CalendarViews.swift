import SwiftUI

struct AgendaSection: View {
    @ObservedObject var agenda: CalendarAgenda
    let openSettings: () -> Void

    var body: some View {
        switch agenda.access {
        case .notDetermined:
            Text("See today's events from your Google and other calendars.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect Calendars…") { agenda.requestAccess() }
        case .denied:
            Text("Amora can't read your calendars.")
                .foregroundStyle(.secondary)
            Button("Open Privacy Settings…") { agenda.openPrivacySettings() }
        case .granted:
            if agenda.accounts.isEmpty {
                Text("No calendars on this Mac yet.")
                    .foregroundStyle(.secondary)
                Button("Add Google Account…") { agenda.openInternetAccounts() }
            } else if agenda.upcoming.isEmpty {
                Text("Nothing on your calendars today or tomorrow")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(agenda.upcoming) { event in
                    AgendaEventRow(
                        event: event,
                        time: agenda.timeLabel(for: event),
                        isImminent: agenda.imminent?.id == event.id
                    )
                }
            }
        }
    }
}

private struct AgendaEventRow: View {
    let event: AgendaEvent
    let time: String
    let isImminent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(event.account) · \(event.calendarTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isImminent ? Color.accentColor : .secondary)
                .fontWeight(isImminent ? .semibold : .regular)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CalendarSettingsSection: View {
    @ObservedObject var agenda: CalendarAgenda

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendars")
                .font(.headline)
            switch agenda.access {
            case .notDetermined:
                note("Amora shows upcoming events in the menu and your pets wave before a meeting starts.")
                Button("Connect Calendars…") { agenda.requestAccess() }
            case .denied:
                note("Calendar access is off. Allow Amora under Privacy & Security › Calendars.")
                Button("Open Privacy Settings…") { agenda.openPrivacySettings() }
            case .granted:
                if agenda.accounts.isEmpty {
                    note("No calendars found on this Mac.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(agenda.accounts) { account in
                                CalendarAccountRows(agenda: agenda, account: account)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: listHeight)
                }
                note("Each Google account you add in System Settings › Internet Accounts appears here.")
                Button("Add Google Account…") { agenda.openInternetAccounts() }
            }
        }
    }

    private var listHeight: CGFloat {
        let rows = agenda.accounts.reduce(0) { $0 + $1.calendars.count + 1 }
        return min(CGFloat(rows) * 24, 220)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CalendarAccountRows: View {
    @ObservedObject var agenda: CalendarAgenda
    let account: AgendaAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            ForEach(account.calendars) { calendar in
                Toggle(calendar.title, isOn: Binding(
                    get: { agenda.isVisible(calendar.id) },
                    set: { agenda.setVisible($0, calendarID: calendar.id) }
                ))
                .accessibilityLabel("Show \(calendar.title) from \(account.name)")
            }
        }
    }
}
