import Foundation
import Testing
@testable import ReminderCore

struct ReminderCSVExporterTests {
    /// Importa, exporta y vuelve a importar: se conservan título, fecha límite y repetición.
    @Test func exportOfDueImportRoundTrips() throws {
        let original = try ReminderCSVImporter.parse(try fixture("due-export.csv"), calendar: mexico).reminders
        let exported = ReminderCSVExporter.csv(for: original, calendar: mexico)
        let result = try ReminderCSVImporter.parse(exported, calendar: mexico)

        #expect(result.issues.isEmpty)
        #expect(result.reminders.count == original.count)
        for (before, after) in zip(original, result.reminders) {
            #expect(after.title == before.title)
            #expect(after.dueDate == before.dueDate)
            #expect(after.repeatRule == before.repeatRule, "\(before.title)")
            #expect(after.completedAt == nil)
        }
    }

    @Test func writesHeaderQuotedFieldsAndCompletion() throws {
        let reminders = [
            Reminder(title: "Nota con \"comillas\", coma y salto\nde línea", dueDate: utc("2026-10-11T03:00:00Z")),
            Reminder(title: "Regar plantas", dueDate: local(2026, 10, 17, 8),
                     repeatRule: RepeatRule(frequency: .weekly, hour: 8, weekdays: [7])),
            Reminder(title: "Renovar seguro", dueDate: utc("2027-04-19T16:00:00Z"),
                     completedAt: utc("2027-04-18T20:15:00Z")),
        ]
        let csv = ReminderCSVExporter.csv(for: reminders, calendar: mexico)
        #expect(csv == """
        "Recordatorio","Fecha límite","Repetir","Completado"\r
        "Nota con ""comillas"", coma y salto
        de línea","2026-10-11T03:00:00Z","",""\r
        "Regar plantas","2026-10-17T14:00:00Z","Todos los sábados 8:00",""\r
        "Renovar seguro","2027-04-19T16:00:00Z","","2027-04-18T20:15:00Z"\r

        """)

        let result = try ReminderCSVImporter.parse(csv, calendar: mexico)
        #expect(result.issues.isEmpty)
        #expect(result.reminders.map(\.title) == reminders.map(\.title))
        #expect(result.reminders.map(\.dueDate) == reminders.map(\.dueDate))
        #expect(result.reminders.map(\.repeatRule) == reminders.map(\.repeatRule))
        #expect(result.reminders.map(\.completedAt) == reminders.map(\.completedAt))
    }

    /// El archivo lleva BOM (para Excel) y se vuelve a leer igual que al importar uno desde Archivos.
    @Test func dataIsUTF8WithBOMAndImportable() throws {
        let reminders = [Reminder(title: "⚠️ Pagar renta", dueDate: utc("2026-10-29T16:00:00Z"),
                                  repeatRule: RepeatRule(frequency: .monthly, hour: 10, dayOfMonth: 29))]
        let data = ReminderCSVExporter.data(for: reminders, calendar: mexico)
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))

        let text = try #require(ReminderCSVImporter.decodeText(data))
        let result = try ReminderCSVImporter.parse(text, calendar: mexico)
        #expect(result.reminders.first?.title == "⚠️ Pagar renta")
        #expect(result.reminders.first?.repeatRule == reminders[0].repeatRule)
    }

    /// Cualquier regla que se pueda crear en la app sobrevive a exportar e importar con su fecha límite.
    @Test(arguments: [
        RepeatRule(frequency: .hourly, hour: 21, minute: 0),
        RepeatRule(frequency: .hourly, interval: 3, hour: 21, minute: 15),
        RepeatRule(frequency: .daily, hour: 23),
        RepeatRule(frequency: .daily, interval: 3, hour: 7, minute: 5),
        RepeatRule(frequency: .weekly, hour: 8, weekdays: [7]),
        RepeatRule(frequency: .weekly, hour: 8, weekdays: [2, 4, 6]),
        RepeatRule(frequency: .weekly, interval: 2, hour: 8, weekdays: [2, 5]),
        RepeatRule(frequency: .weekly, hour: 6, minute: 30, weekdays: RepeatRule.workdays),
        RepeatRule(frequency: .weekly, hour: 10, weekdays: RepeatRule.weekendDays),
        RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 7),
        RepeatRule(frequency: .monthly, interval: 2, hour: 9, dayOfMonth: 1),
        RepeatRule(frequency: .monthly, hour: 18, dayOfMonth: 31, lastDayOfMonth: true),
        RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11),
        RepeatRule(frequency: .yearly, interval: 2, hour: 13, dayOfMonth: 1, month: 2),
    ])
    func repeatRulesRoundTrip(rule: RepeatRule) throws {
        let due = try #require(rule.nextOccurrence(after: local(2026, 10, 10, 21), calendar: mexico))
        let reminder = Reminder(title: "Prueba", dueDate: due, repeatRule: rule)
        let csv = ReminderCSVExporter.csv(for: [reminder], calendar: mexico)
        let imported = try #require(try ReminderCSVImporter.parse(csv, calendar: mexico).reminders.first)

        #expect(imported.dueDate == due)
        let importedRule = try #require(imported.repeatRule, "\(rule.summary(calendar: mexico))")
        #expect(importedRule.occurrences(after: due, count: 12, calendar: mexico)
            == rule.occurrences(after: due, count: 12, calendar: mexico))
    }

    @Test func suggestsDatedFileName() {
        #expect(ReminderCSVExporter.fileName(date: local(2026, 10, 13, 9), calendar: mexico) == "Recordatorios 2026-10-13")
    }
}
