import Foundation
import Testing
@testable import ReminderCore

struct ReminderCSVImporterTests {
    @Test func importsDueExport() throws {
        let result = try ReminderCSVImporter.parse(try fixture("due-export.csv"), calendar: mexico)
        #expect(result.issues.isEmpty)
        #expect(result.entries.count == 19)

        let byTitle = Dictionary(uniqueKeysWithValues: result.reminders.map { ($0.title, $0) })

        let plants = try #require(byTitle["Regar plantas"])
        #expect(plants.dueDate == utc("2026-10-11T03:00:00Z"))
        #expect(plants.repeatRule == RepeatRule(frequency: .weekly, hour: 8, weekdays: [7]))

        let car = try #require(byTitle["Lavar coche"])
        #expect(car.repeatRule == RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 7))

        let tires = try #require(byTitle["Presión de llantas"])
        #expect(tires.repeatRule == RepeatRule(frequency: .monthly, interval: 2, hour: 9, dayOfMonth: 1))
        #expect(tires.dueDate == local(2026, 12, 1, 9))

        let birthday = try #require(byTitle["Tarjeta de cumpleaños"])
        #expect(birthday.repeatRule == RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11))

        #expect(byTitle["⚠️  Pagar tarjeta | Max 5 del mes"]?.repeatRule?.dayOfMonth == 3)
        #expect(byTitle["Preparar material, proyector y café"]?.repeatRule?.weekdays == [1])
        #expect(byTitle["Renovar seguro"]?.repeatRule == nil)
        #expect(byTitle["Nota con \"comillas\" y salto\nde línea"] != nil)
    }

    /// La fecha límite de cada recordatorio repetitivo coincide con su regla (hora local de México), salvo los
    /// que en el ejemplo están pospuestos, como pasa en una exportación real.
    @Test func dueDatesAgreeWithParsedRules() throws {
        let result = try ReminderCSVImporter.parse(try fixture("due-export.csv"), calendar: mexico)
        let postponed: Set = ["Regar plantas", "Lavar coche", "$50 para la colecta"]
        for reminder in result.reminders where !postponed.contains(reminder.title) {
            guard let rule = reminder.repeatRule else { continue }
            #expect(rule.firstOccurrence(onOrAfter: reminder.dueDate, calendar: mexico) == reminder.dueDate, "\(reminder.title)")
        }
    }

    @Test func reportsBadRowsAndUnknownRepetitions() throws {
        let csv = """
        Recordatorio,Fecha límite,Repetir
        Sin fecha,,
        Fecha mala,mañana,
        ,2026-10-11T03:00:00Z,
        Raro,2026-10-11T03:00:00Z,Cada 30 minutos
        Bien,2026-10-11 09:30,Diariamente 9:30
        """
        let result = try ReminderCSVImporter.parse(csv, calendar: mexico)
        #expect(result.reminders.map(\.title) == ["Raro", "Bien"])
        #expect(result.reminders[0].repeatRule == nil)
        #expect(result.reminders[1].dueDate == local(2026, 10, 11, 9, 30))
        #expect(result.issues.map(\.kind) == [.skipped, .skipped, .skipped, .repeatNotRecognized])
        #expect(result.issues.map(\.line) == [2, 3, 4, 5])
    }

    @Test func acceptsEnglishHeadersInAnyOrder() throws {
        let csv = "Repeat,Due Date,Reminder\nDaily 7:00,2026-10-11T13:00:00Z,Stretch\n"
        let result = try ReminderCSVImporter.parse(csv, calendar: mexico)
        #expect(result.reminders.first?.title == "Stretch")
        #expect(result.reminders.first?.repeatRule == RepeatRule(frequency: .daily, hour: 7))
    }

    @Test func worksWithoutHeader() throws {
        let csv = "\"Comprar pan\",\"2026-10-11T15:00:00Z\",\"\"\n"
        let result = try ReminderCSVImporter.parse(csv, calendar: mexico)
        #expect(result.reminders.map(\.title) == ["Comprar pan"])
    }

    @Test func decodesCommonEncodings() throws {
        let text = "Recordatorio,Fecha límite\nCafé,2026-10-11T15:00:00Z\n"
        #expect(ReminderCSVImporter.decodeText(Data(text.utf8)) == text)
        #expect(ReminderCSVImporter.decodeText(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))?.hasSuffix(text) == true)
        let utf16 = try #require(text.data(using: .utf16))
        #expect(ReminderCSVImporter.decodeText(utf16) == text)
        let latin = try #require(text.data(using: .windowsCP1252))
        #expect(ReminderCSVImporter.decodeText(latin) == text)
    }

    @Test func emptyFileThrows() {
        #expect(throws: ReminderCSVImporter.ImportError.empty) {
            try ReminderCSVImporter.parse("", calendar: mexico)
        }
    }

    @Test func prepareSkipsDuplicatesAndAdvancesPastDueRepeating() throws {
        let now = utc("2026-10-11T15:00:00Z") // 11 oct, 9:00 en México
        let result = try ReminderCSVImporter.parse(try fixture("due-export.csv"), calendar: mexico)
        let existing = [
            Reminder(title: "  regar   PLANTAS ", dueDate: utc("2026-10-11T03:00:00Z")),
            // Ya se completó una vez y avanzó de fecha, pero es el mismo recordatorio repetitivo.
            Reminder(title: "Comprar fruta", dueDate: local(2026, 10, 23, 11),
                     repeatRule: RepeatRule(frequency: .weekly, hour: 11, weekdays: [6])),
            // Mismo título pero otra regla: no es duplicado.
            Reminder(title: "Lavar coche", dueDate: local(2026, 11, 7, 20),
                     repeatRule: RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 8)),
        ]

        let prepared = ReminderCSVImporter.prepare(
            result.reminders, existing: existing, skipDuplicates: true, advancePastDueRepeating: true,
            now: now, calendar: mexico
        )
        #expect(prepared.duplicates == 2)
        #expect(prepared.reminders.count == 17)
        #expect(!prepared.reminders.contains { $0.title == "Comprar fruta" })

        let byTitle = Dictionary(uniqueKeysWithValues: prepared.reminders.map { ($0.title, $0) })
        // Repetitivo vencido: pasa a la siguiente ocurrencia futura.
        #expect(byTitle["Tomar vitaminas"]?.dueDate == local(2026, 10, 11, 23))
        #expect(byTitle["$50 para la colecta"]?.dueDate == local(2026, 10, 17, 10))
        // No repetitivo vencido: se queda como estaba.
        #expect(byTitle["Escribir artículo: un estilo brutalista"]?.dueDate == utc("2026-10-11T03:00:00Z"))
        // Futuro: sin cambios.
        #expect(byTitle["Lavar coche"]?.dueDate == utc("2026-10-12T03:00:00Z"))

        let again = ReminderCSVImporter.prepare(
            result.reminders + result.reminders, existing: [], skipDuplicates: true, advancePastDueRepeating: false
        )
        #expect(again.reminders.count == 19)
        #expect(again.duplicates == 19)
    }
}
