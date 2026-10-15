import Foundation
import Testing
@testable import ReminderCore

struct ReminderExtractionTests {
    /// Miércoles 14 de octubre de 2026, 18:05 en la Ciudad de México.
    let now = local(2026, 10, 14, 18, 5)

    private func parse(_ json: String) throws -> [ReminderExtraction.Draft] {
        try ReminderExtraction.parse(json, now: now, calendar: mexico)
    }

    @Test func readsSeveralRemindersWithRepetitions() throws {
        let drafts = try parse("""
        {"reminders":[
          {"title":"Llamar al dentista","due":"2026-10-15T09:00","repeat":null},
          {"title":"Sacar la basura","due":"2026-10-19T20:00",
           "repeat":{"frequency":"weekly","interval":1,"weekdays":["monday","thursday"]}},
          {"title":"Pagar la renta","due":"2026-10-31T10:00",
           "repeat":{"frequency":"monthly","last_day_of_month":true}},
          {"title":"Cumpleaños de Ana","due":"2027-03-08T08:00",
           "repeat":{"frequency":"yearly","day_of_month":8,"month":3}}
        ]}
        """)
        #expect(drafts.map(\.reminder.title) == ["Llamar al dentista", "Sacar la basura", "Pagar la renta", "Cumpleaños de Ana"])
        #expect(drafts.allSatisfy { $0.notes.isEmpty })

        #expect(drafts[0].reminder.dueDate == local(2026, 10, 15, 9))
        #expect(drafts[0].reminder.repeatRule == nil)

        #expect(drafts[1].reminder.repeatRule == RepeatRule(frequency: .weekly, hour: 20, weekdays: [2, 5]))
        #expect(drafts[1].reminder.dueDate == local(2026, 10, 19, 20))

        #expect(drafts[2].reminder.repeatRule == RepeatRule(frequency: .monthly, hour: 10, dayOfMonth: 31, lastDayOfMonth: true))
        #expect(drafts[2].reminder.dueDate == local(2026, 10, 31, 10))

        #expect(drafts[3].reminder.repeatRule == RepeatRule(frequency: .yearly, hour: 8, dayOfMonth: 8, month: 3))
        #expect(drafts[3].reminder.dueDate == local(2027, 3, 8, 8))
    }

    @Test func readsWeekdayOfMonth() throws {
        let drafts = try parse("""
        {"reminders":[
          {"title":"Junta de vecinos","due":"2026-10-25T10:00",
           "repeat":{"frequency":"monthly","weekdays":["sunday"],"week_of_month":-1}},
          {"title":"Pagar club","due":"2026-11-03T09:00",
           "repeat":{"frequency":"monthly","interval":2,"week_of_month":1}}
        ]}
        """)
        #expect(drafts[0].reminder.repeatRule == RepeatRule(frequency: .monthly, hour: 10, weekdayOrdinal: -1, ordinalWeekday: 1))
        // Sin día de la semana se toma el de "due" (martes).
        #expect(drafts[1].reminder.repeatRule == RepeatRule(frequency: .monthly, interval: 2, hour: 9, weekdayOrdinal: 1, ordinalWeekday: 3))
    }

    @Test func toleratesWrappersAndLooseTypes() throws {
        let drafts = try parse("""
        <think>El usuario quiere dos cosas…</think>
        Claro, aquí están:
        ```json
        [
          {"titulo":"  Regar plantas ","fecha":"2026-10-17 08:30","repetir":{"frecuencia":"cada semana","interval":"2","dias":[6,"dom"]}},
          {"title":"Tomar pastilla","due":"2026-10-14T21:00:00-06:00","repeat":{"frequency":"hourly","interval":8.0}},
          {"due":"2026-10-15T09:00"}
        ]
        ```
        """)
        #expect(drafts.map(\.reminder.title) == ["Regar plantas", "Tomar pastilla"])
        let plants = try #require(drafts.first { $0.reminder.title == "Regar plantas" })
        // 6 = sábado y 7 (domingo) en numeración ISO; en Calendar son 7 y 1.
        #expect(plants.reminder.repeatRule == RepeatRule(frequency: .weekly, interval: 2, hour: 8, minute: 30, weekdays: [7, 1]))
        #expect(plants.reminder.dueDate == local(2026, 10, 17, 8, 30))

        let pill = try #require(drafts.first { $0.reminder.title == "Tomar pastilla" })
        #expect(pill.reminder.dueDate == local(2026, 10, 14, 21))
        #expect(pill.reminder.repeatRule == RepeatRule(frequency: .hourly, interval: 8, hour: 21))
    }

    /// Con intervalo mayor que 1, la fecha que ya cae en la repetición no se recorre aunque esté al inicio del periodo.
    @Test func keepsDueDatesThatStartAPeriod() throws {
        let drafts = try parse("""
        {"reminders":[
          {"title":"Cada 2 domingos","due":"2026-10-18T00:00","repeat":{"frequency":"weekly","interval":2,"weekdays":["sunday"]}},
          {"title":"Cada 2 meses","due":"2026-11-01T00:00","repeat":{"frequency":"monthly","interval":2,"day_of_month":1}},
          {"title":"Cada 2 lunes","due":"2026-10-15T09:00","repeat":{"frequency":"weekly","interval":2,"weekdays":"lun"}}
        ]}
        """)
        #expect(drafts[0].reminder.dueDate == local(2026, 10, 18))
        #expect(drafts[1].reminder.dueDate == local(2026, 11, 1))
        // Dicho un jueves, empieza el lunes siguiente (no dentro de dos semanas).
        #expect(drafts[2].reminder.dueDate == local(2026, 10, 19, 9))
        #expect(drafts[2].reminder.repeatRule?.weekdays == [2])
    }

    @Test func weekdayNamesNumbersAndAbbreviations() {
        #expect(["monday", "Martes", "mié", "jue.", "fri", "sa", "domingo", "1", "7"].map(ReminderExtraction.weekday(from:))
            == [2, 3, 4, 5, 6, 7, 1, 2, 1])
        #expect(ReminderExtraction.weekday(from: "s") == nil)
        #expect(ReminderExtraction.weekday(from: "8") == nil)
        #expect(ReminderExtraction.weekday(from: "luna") == nil)
    }

    @Test func numericTitlesAreKeptAndUntitledItemsAreSkipped() throws {
        let drafts = try parse(#"{"reminders":[{"title":42,"due":"2026-10-15T09:00"},{"due":"2026-10-15T09:00"},{"title":"   "}]}"#)
        #expect(drafts.map(\.reminder.title) == ["42"])
    }

    @Test func repeatCanBeTextOrAFrequencyWord() throws {
        let drafts = try parse("""
        {"reminders":[
          {"title":"Junta","due":"2026-10-19T09:00","repeat":"Entre semana 9:00"},
          {"title":"Agua","due":"2026-10-15T07:00","repeat":"daily"},
          {"title":"Cobro","due":"2026-11-01T12:00","repeat":"quincenal"},
          {"title":"Raro","due":"2026-10-15T07:00","repeat":"cuando llueva"}
        ]}
        """)
        #expect(drafts[0].reminder.repeatRule == RepeatRule(frequency: .weekly, hour: 9, weekdays: RepeatRule.workdays))
        #expect(drafts[0].reminder.dueDate == local(2026, 10, 19, 9))
        #expect(drafts[1].reminder.repeatRule == RepeatRule(frequency: .daily, hour: 7))
        #expect(drafts[2].reminder.repeatRule == RepeatRule(frequency: .weekly, interval: 2, hour: 12, weekdays: [1]))
        #expect(drafts[3].reminder.repeatRule == nil)
        #expect(drafts[3].notes == [.unrecognizedRepeat("cuando llueva")])
        #expect(drafts[3].notes.map(\.message) == ["No se entendió la repetición «cuando llueva»: revísala."])
    }

    @Test func emptyOrNoneRepeatMeansNoRepetition() throws {
        let drafts = try parse("""
        {"reminders":[
          {"title":"A","due":"2026-10-15T07:00","repeat":{}},
          {"title":"B","due":"2026-10-15T07:00","repeat":{"frequency":"none"}},
          {"title":"C","due":"2026-10-15T07:00","repeat":"nunca"},
          {"title":"D","due":"2026-10-15T07:00"}
        ]}
        """)
        #expect(drafts.allSatisfy { $0.reminder.repeatRule == nil && $0.notes.isEmpty })
    }

    @Test func weekdaysFrequencyWordMeansMondayToFriday() throws {
        let drafts = try parse(#"{"reminders":[{"title":"Ejercicio","due":"2026-10-15T07:00","repeat":{"frequency":"weekdays"}}]}"#)
        #expect(drafts[0].reminder.repeatRule?.weekdays == RepeatRule.workdays)
        #expect(drafts[0].reminder.repeatRule?.frequency == .weekly)
    }

    @Test func missingOrBadDatesFallBackToTheNextHourWithANote() throws {
        let drafts = try parse(#"{"reminders":[{"title":"Sin fecha"},{"title":"Fecha rara","due":"pasado mañana"},{"title":"Sólo día","due":"2026-10-20"}]}"#)
        #expect(drafts[0].reminder.dueDate == local(2026, 10, 14, 19))
        #expect(drafts[0].notes == [.missingDate])
        #expect(drafts[1].reminder.dueDate == local(2026, 10, 14, 19))
        #expect(drafts[1].notes == [.unrecognizedDate("pasado mañana")])
        #expect(drafts[1].notes.allSatisfy { $0.isAboutDate })
        #expect(drafts[1].notes.map(\.message) == ["No se entendió la fecha «pasado mañana»: revisa la fecha y hora."])
        #expect(drafts[2].reminder.dueDate == local(2026, 10, 20, 9))
        #expect(drafts[2].notes.isEmpty)
    }

    @Test func pastDatesAreKeptOrAdvancedWhenTheyRepeat() throws {
        let drafts = try parse("""
        {"reminders":[
          {"title":"Ya pasó","due":"2026-10-14T08:00"},
          {"title":"Diario","due":"2026-10-14T08:00","repeat":{"frequency":"daily"}}
        ]}
        """)
        #expect(drafts[0].reminder.dueDate == local(2026, 10, 14, 8))
        #expect(drafts[0].reminder.isOverdue(now: now))
        #expect(drafts[0].notes.isEmpty)
        #expect(drafts[1].reminder.dueDate == local(2026, 10, 15, 8))
        #expect(drafts[1].notes.isEmpty)
    }

    @Test func emptyListAndSingleObject() throws {
        #expect(try parse(#"{"reminders":[]}"#).isEmpty)
        let single = try parse(#"{"title":"Uno solo","due":"2026-10-15T10:00"}"#)
        #expect(single.map(\.reminder.title) == ["Uno solo"])
    }

    @Test func invalidResponsesThrow() {
        #expect(throws: ReminderExtraction.ExtractionError.invalidJSON) { try parse("No encontré recordatorios.") }
        #expect(throws: ReminderExtraction.ExtractionError.invalidJSON) { try parse(#"{"answer":"nada"}"#) }
        #expect(throws: ReminderExtraction.ExtractionError.invalidJSON) { try parse("{reminders: [}") }
    }

    @Test func promptCarriesTheCurrentDateAndUpcomingDays() {
        let prompt = ReminderExtraction.systemPrompt(now: now, calendar: mexico, withImages: false)
        #expect(prompt.contains("Ahora es miércoles 14 de octubre de 2026, 18:05 (hora local; zona horaria America/Mexico_City, UTC−06:00)."))
        #expect(prompt.contains("- hoy miércoles 14 de octubre = 2026-10-14"))
        #expect(prompt.contains("- mañana jueves 15 de octubre = 2026-10-15"))
        #expect(prompt.contains("- martes 27 de octubre = 2026-10-27"))
        #expect(!prompt.contains("2026-10-28"))
        #expect(prompt.contains(#"{"reminders":[{"title":"Llamar al dentista","due":"2026-10-15T09:00","repeat":null}]}"#))
        #expect(!prompt.contains("fotos"))

        let photo = ReminderExtraction.systemPrompt(now: now, calendar: mexico, withImages: true)
        #expect(photo.contains("Las indicaciones del usuario mandan"))
        #expect(photo.hasSuffix(#"- Si no hay nada que recordar, responde {"reminders":[]}."#))
    }

    @Test func userPromptDependsOnTheSource() {
        #expect(ReminderExtraction.userPrompt(text: " Comprar pan \n", withImages: false) == "Nota:\nComprar pan")
        #expect(ReminderExtraction.userPrompt(text: "", withImages: true) == "Sin indicaciones: crea los recordatorios a partir de las fotos.")
        #expect(ReminderExtraction.userPrompt(text: "Sólo lo del viernes", withImages: true) == "Indicaciones:\nSólo lo del viernes")
    }

    @Test func utcOffsetFormatting() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        #expect(ReminderExtraction.utcOffset(of: kolkata, at: now) == "UTC+05:30")
        #expect(ReminderExtraction.utcOffset(of: TimeZone(identifier: "UTC")!, at: now) == "UTC+00:00")
    }
}
