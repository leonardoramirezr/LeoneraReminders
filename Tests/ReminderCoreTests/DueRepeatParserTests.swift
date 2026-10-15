import Foundation
import Testing
@testable import ReminderCore

struct DueRepeatParserTests {
    /// Sábado 10 de octubre de 2026, 21:00 (hora de México).
    let due = local(2026, 10, 10, 21, 0)

    func parse(_ text: String) -> DueRepeatParser.Result {
        DueRepeatParser.parse(text, dueDate: due, calendar: mexico)
    }

    @Test(arguments: [
        ("Diariamente 23:00", RepeatRule(frequency: .daily, hour: 23, minute: 0)),
        ("Diariamente 23:30", RepeatRule(frequency: .daily, hour: 23, minute: 30)),
        ("Todos los sábados 8:00", RepeatRule(frequency: .weekly, hour: 8, weekdays: [7])),
        ("Todos los domingos 8:10", RepeatRule(frequency: .weekly, hour: 8, minute: 10, weekdays: [1])),
        ("Todos los miércoles 17:30", RepeatRule(frequency: .weekly, hour: 17, minute: 30, weekdays: [4])),
        ("Todos los viernes 11:00", RepeatRule(frequency: .weekly, hour: 11, weekdays: [6])),
        ("7mo de cada mes a las 20:00", RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 7)),
        ("16to de cada mes a las 21:00", RepeatRule(frequency: .monthly, hour: 21, dayOfMonth: 16)),
        ("29no de cada mes a las 10:00", RepeatRule(frequency: .monthly, hour: 10, dayOfMonth: 29)),
        ("1er de cada mes a las 13:00", RepeatRule(frequency: .monthly, hour: 13, dayOfMonth: 1)),
        ("3er de cada mes a las 21:00", RepeatRule(frequency: .monthly, hour: 21, dayOfMonth: 3)),
        ("6to de cada mes a las 22:30", RepeatRule(frequency: .monthly, hour: 22, minute: 30, dayOfMonth: 6)),
        ("1er de cada 2 meses a las 9:00", RepeatRule(frequency: .monthly, interval: 2, hour: 9, dayOfMonth: 1)),
        ("1er de cada 3 meses a las 23:00", RepeatRule(frequency: .monthly, interval: 3, hour: 23, dayOfMonth: 1)),
        ("Todos los 8 nov, 20:20", RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11)),
        ("Todos los 1 dic, 20:50", RepeatRule(frequency: .yearly, hour: 20, minute: 50, dayOfMonth: 1, month: 12)),
        ("Todos los 1 feb, 13:00", RepeatRule(frequency: .yearly, hour: 13, dayOfMonth: 1, month: 2)),
        ("Todos los 14 jun, 11:00", RepeatRule(frequency: .yearly, hour: 11, dayOfMonth: 14, month: 6)),
        ("Todos los 28 jul, 10:00", RepeatRule(frequency: .yearly, hour: 10, dayOfMonth: 28, month: 7)),
    ])
    func parsesDueExportFormats(text: String, expected: RepeatRule) {
        #expect(parse(text) == .rule(expected))
    }

    @Test(arguments: [
        ("Todos los lunes, miércoles y viernes 7:15", RepeatRule(frequency: .weekly, hour: 7, minute: 15, weekdays: [2, 4, 6])),
        ("Cada 2 semanas el lunes 9:00", RepeatRule(frequency: .weekly, interval: 2, hour: 9, weekdays: [2])),
        ("Cada dos semanas los jueves 9:00", RepeatRule(frequency: .weekly, interval: 2, hour: 9, weekdays: [5])),
        ("Entre semana 6:30", RepeatRule(frequency: .weekly, hour: 6, minute: 30, weekdays: [2, 3, 4, 5, 6])),
        ("Fines de semana 10:00", RepeatRule(frequency: .weekly, hour: 10, weekdays: [1, 7])),
        ("Todos los días 7:00", RepeatRule(frequency: .daily, hour: 7)),
        ("Cada 3 días 7:00", RepeatRule(frequency: .daily, interval: 3, hour: 7)),
        ("Último día de cada mes a las 18:00", RepeatRule(frequency: .monthly, hour: 18, dayOfMonth: 31, lastDayOfMonth: true)),
        ("Cada 2 horas", RepeatRule(frequency: .hourly, interval: 2, hour: 21, minute: 0)),
        ("Cada año el 8 de noviembre, 20:20", RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11)),
        ("Cada 2 años el 8 de noviembre, 20:20", RepeatRule(frequency: .yearly, interval: 2, hour: 20, minute: 20, dayOfMonth: 8, month: 11)),
        ("Mensualmente", RepeatRule(frequency: .monthly, hour: 21, dayOfMonth: 10)),
        ("Semanalmente", RepeatRule(frequency: .weekly, hour: 21, weekdays: [7])),
        ("Every Saturday at 8:00 AM", RepeatRule(frequency: .weekly, hour: 8, weekdays: [7])),
        ("Daily 11:00 PM", RepeatRule(frequency: .daily, hour: 23)),
        ("1st of every month at 20:00", RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 1)),
        ("Every 2 months on the 15th", RepeatRule(frequency: .monthly, interval: 2, hour: 21, dayOfMonth: 15)),
        ("Primer lunes de cada mes a las 9:00", RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: 1, ordinalWeekday: 2)),
        ("3er viernes de cada mes 18:00", RepeatRule(frequency: .monthly, hour: 18, weekdayOrdinal: 3, ordinalWeekday: 6)),
        ("Último domingo de cada 3 meses a las 10:00", RepeatRule(frequency: .monthly, interval: 3, hour: 10, weekdayOrdinal: -1, ordinalWeekday: 1)),
        ("Penúltimo jueves de cada mes", RepeatRule(frequency: .monthly, hour: 21, weekdayOrdinal: -2, ordinalWeekday: 5)),
        ("Last Friday of every month at 17:00", RepeatRule(frequency: .monthly, hour: 17, weekdayOrdinal: -1, ordinalWeekday: 6)),
        ("Every Nov 8, 20:20", RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11)),
    ])
    func parsesOtherVariants(text: String, expected: RepeatRule) {
        #expect(parse(text) == .rule(expected))
    }

    @Test func emptyOrNeverMeansNoRepetition() {
        #expect(parse("") == .none)
        #expect(parse("   ") == .none)
        #expect(parse("Nunca") == .none)
    }

    @Test func unknownTextIsReported() {
        #expect(parse("Cada 30 minutos") == .unrecognized)
        #expect(parse("Al completar") == .unrecognized)
    }

    /// Lo que la app muestra como resumen también se puede volver a leer.
    @Test(arguments: [
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
        RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -1, ordinalWeekday: 1),
        RepeatRule(frequency: .monthly, interval: 2, hour: 9, weekdayOrdinal: 2, ordinalWeekday: 3),
        RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: 4, ordinalWeekday: 6),
        RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -2, ordinalWeekday: 4),
        RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -3, ordinalWeekday: 7),
        RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11),
        RepeatRule(frequency: .yearly, interval: 2, hour: 13, dayOfMonth: 1, month: 2),
        RepeatRule(frequency: .hourly, hour: 21, minute: 0),
        RepeatRule(frequency: .hourly, interval: 3, hour: 21, minute: 15),
    ])
    func summaryRoundTrips(rule: RepeatRule) {
        #expect(parse(rule.summary(calendar: mexico)) == .rule(rule), "\(rule.summary(calendar: mexico))")
    }

    @Test func summariesReadNaturally() {
        #expect(RepeatRule(frequency: .weekly, hour: 8, weekdays: [7]).summary(calendar: mexico) == "Todos los sábados 8:00")
        #expect(RepeatRule(frequency: .weekly, hour: 8, weekdays: [2, 4, 6]).summary(calendar: mexico)
            == "Todos los lunes, miércoles y viernes 8:00")
        #expect(RepeatRule(frequency: .monthly, interval: 2, hour: 9, dayOfMonth: 1).summary(calendar: mexico)
            == "Día 1 de cada 2 meses a las 9:00")
        #expect(RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -1, ordinalWeekday: 1).summary(calendar: mexico)
            == "Último domingo de cada mes a las 9:00")
        #expect(RepeatRule(frequency: .monthly, interval: 2, hour: 9, weekdayOrdinal: -3, ordinalWeekday: 4).summary(calendar: mexico)
            == "Antepenúltimo miércoles de cada 2 meses a las 9:00")
        #expect(RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11).summary(calendar: mexico)
            == "Cada año el 8 de noviembre, 20:20")
    }
}
