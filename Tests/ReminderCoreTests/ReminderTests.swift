import Foundation
import Testing
@testable import ReminderCore

struct ReminderTests {
    @Test func completingOneOffReminderMarksItDone() {
        var reminder = Reminder(title: "Renovar seguro", dueDate: local(2026, 10, 10, 9))
        reminder.snooze(by: .minutes(10), now: local(2026, 10, 10, 9), calendar: mexico)
        reminder.complete(now: local(2026, 10, 10, 9, 5), calendar: mexico)
        #expect(reminder.isCompleted)
        #expect(reminder.snoozedUntil == nil)
        #expect(reminder.dueDate == local(2026, 10, 10, 9))
    }

    @Test func completingRepeatingReminderMovesToNextOccurrence() {
        var reminder = Reminder(
            title: "Lavar coche",
            dueDate: local(2026, 10, 11, 21),
            repeatRule: RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 7)
        )
        reminder.complete(now: local(2026, 10, 11, 21, 3), calendar: mexico)
        #expect(!reminder.isCompleted)
        #expect(reminder.dueDate == local(2026, 11, 7, 20))
        #expect(reminder.lastCompletedAt == local(2026, 10, 11, 21, 3))
    }

    @Test func completingLateSkipsMissedOccurrences() {
        var reminder = Reminder(
            title: "Vitaminas",
            dueDate: local(2026, 10, 10, 23),
            repeatRule: RepeatRule(frequency: .daily, hour: 23)
        )
        reminder.complete(now: local(2026, 10, 13, 8), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 13, 23))
    }

    @Test func completingEarlyGoesToTheFollowingOccurrence() {
        var reminder = Reminder(
            title: "Regar plantas",
            dueDate: local(2026, 10, 17, 8),
            repeatRule: RepeatRule(frequency: .weekly, hour: 8, weekdays: [7])
        )
        reminder.complete(now: local(2026, 10, 15, 12), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 24, 8))
    }

    @Test func snoozeChangesOnlyTheAlertDate() {
        var reminder = Reminder(title: "Comprar fruta", dueDate: local(2026, 10, 16, 11))
        reminder.snooze(by: .minutes(20), now: local(2026, 10, 16, 11, 1), calendar: mexico)
        #expect(reminder.dueDate == local(2026, 10, 16, 11))
        #expect(reminder.alertDate == local(2026, 10, 16, 11, 21))
        #expect(!reminder.isOverdue(now: local(2026, 10, 16, 11, 10)))
        #expect(reminder.isOverdue(now: local(2026, 10, 16, 11, 21)))
    }

    @Test func rescheduleClearsSnoozeAndCompletion() {
        var reminder = Reminder(title: "Algo", dueDate: local(2026, 10, 16, 11))
        reminder.snooze(by: .hours(1), now: local(2026, 10, 16, 11), calendar: mexico)
        reminder.complete(now: local(2026, 10, 16, 11), calendar: mexico)
        reminder.reschedule(to: local(2026, 10, 18, 10))
        #expect(!reminder.isCompleted)
        #expect(reminder.alertDate == local(2026, 10, 18, 10))
    }

    @Test func advancePastDueRepetitionOnlyTouchesOverdueRepeatingReminders() {
        let now = local(2026, 10, 11, 9)
        var overdue = Reminder(title: "Fotos", dueDate: local(2026, 10, 10, 21),
                               repeatRule: RepeatRule(frequency: .weekly, hour: 8, weekdays: [7]))
        let overdueChanged = overdue.advancePastDueRepetition(now: now, calendar: mexico)
        #expect(overdueChanged)
        #expect(overdue.dueDate == local(2026, 10, 17, 8))

        var oneOff = Reminder(title: "Una vez", dueDate: local(2026, 10, 10, 21))
        let oneOffChanged = oneOff.advancePastDueRepetition(now: now, calendar: mexico)
        #expect(!oneOffChanged)

        var future = Reminder(title: "Futuro", dueDate: local(2026, 10, 12, 8),
                              repeatRule: RepeatRule(frequency: .daily, hour: 8))
        let futureChanged = future.advancePastDueRepetition(now: now, calendar: mexico)
        #expect(!futureChanged)
        #expect(future.dueDate == local(2026, 10, 12, 8))
    }

    @Test func decodesOlderDataWithoutOptionalFields() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Hola","dueDate":0}"#
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
        #expect(reminder.title == "Hola")
        #expect(reminder.repeatRule == nil)
        #expect(reminder.scheduledAlarm == nil)
    }
}

struct QuickAdjustGridTests {
    let grid = QuickAdjustGrid.default
    let start = local(2026, 10, 16, 11, 7)

    @Test func defaultLayoutMatchesTheRequestedMatrix() {
        let labels = grid.rows.map { row in row.map { "\($0.labelParts.value) \($0.labelParts.unit)".trimmingCharacters(in: .whitespaces) } }
        #expect(labels == [
            ["10:00", "14:00", "18:00", "21:00"],
            ["+10 min", "+1 h", "+1 día", "+1 sem."],
            ["−10 min", "−1 h", "−1 día", "−1 sem."],
        ])
    }

    @Test func cellsAdjustTheDate() {
        let rows = grid.rows
        #expect(rows[0][0].apply(to: start, calendar: mexico) == local(2026, 10, 16, 10, 0))
        #expect(rows[0][3].apply(to: start, calendar: mexico) == local(2026, 10, 16, 21, 0))
        #expect(rows[1][0].apply(to: start, calendar: mexico) == local(2026, 10, 16, 11, 17))
        #expect(rows[1][2].apply(to: start, calendar: mexico) == local(2026, 10, 17, 11, 7))
        #expect(rows[1][3].apply(to: start, calendar: mexico) == local(2026, 10, 23, 11, 7))
        #expect(rows[2][1].apply(to: start, calendar: mexico) == local(2026, 10, 16, 10, 7))
        #expect(rows[2][3].apply(to: start, calendar: mexico) == local(2026, 10, 9, 11, 7))
    }

    @Test func setCellReplacesOnlyThatCell() {
        var custom = QuickAdjustGrid(times: [], additions: [.minutes(5)], subtractions: [])
        custom.setCell(.setTime(TimeOfDay(hour: 7, minute: 30)), column: 2)
        custom.setCell(.subtract(.days(3)), column: 3)
        custom.setCell(.add(.hours(9)), column: 7)
        #expect(custom.times == [TimeOfDay(hour: 10), TimeOfDay(hour: 14), TimeOfDay(hour: 7, minute: 30), TimeOfDay(hour: 21)])
        #expect(custom.additions == [.minutes(5), .hours(1), .days(1), .weeks(1)])
        #expect(custom.subtractions == [.minutes(10), .hours(1), .days(1), .days(3)])
    }

    @Test func shortArraysArePaddedWithDefaults() {
        let custom = QuickAdjustGrid(times: [TimeOfDay(hour: 7, minute: 30)], additions: [], subtractions: [.days(2)])
        #expect(custom.rows.map(\.count) == [4, 4, 4])
        #expect(custom.rows[0][0] == .setTime(TimeOfDay(hour: 7, minute: 30)))
        #expect(custom.rows[0][1] == .setTime(TimeOfDay(hour: 14)))
        #expect(custom.rows[2][0] == .subtract(.days(2)))
    }
}

struct AppSettingsTests {
    @Test func defaultsMatchTheRequestedSnoozeOptions() {
        #expect(AppSettings.default.sortedSnoozeOptions.map(\.shortLabel)
            == ["1 min", "5 min", "10 min", "20 min", "40 min", "60 min", "2 h", "3 h"])
        #expect(AppSettings.default.stopAction == .complete)
        #expect(AppSettings.default.secondaryAction == .snooze)
    }

    @Test func decodingMissingKeysFallsBackToDefaults() throws {
        let json = #"{"defaultSnooze":{"value":5,"unit":"minute"},"stopAction":"snooze"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.defaultSnooze == .minutes(5))
        #expect(settings.stopAction == .snooze)
        #expect(settings.secondaryAction == AppSettings.default.secondaryAction)
        #expect(settings.quickAdjustGrid == .default)
    }

    @Test func sortedSnoozeOptionsRemovesDuplicates() {
        var settings = AppSettings.default
        settings.snoozeOptions = [.hours(1), .minutes(5), .hours(1), .minutes(1)]
        #expect(settings.sortedSnoozeOptions == [.minutes(1), .minutes(5), .hours(1)])
    }
}
