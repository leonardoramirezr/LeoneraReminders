import Foundation
import Testing
@testable import ReminderCore

struct RepeatRuleTests {
    @Test func dailyNextOccurrence() {
        let rule = RepeatRule(frequency: .daily, hour: 23, minute: 30)
        #expect(rule.nextOccurrence(after: local(2026, 10, 10, 21), calendar: mexico) == local(2026, 10, 10, 23, 30))
        #expect(rule.nextOccurrence(after: local(2026, 10, 10, 23, 30), calendar: mexico) == local(2026, 10, 11, 23, 30))
    }

    @Test func everyThreeDaysCountsFromCurrentOccurrence() {
        let rule = RepeatRule(frequency: .daily, interval: 3, hour: 7)
        #expect(rule.occurrences(after: local(2026, 10, 10, 7), count: 2, calendar: mexico)
            == [local(2026, 10, 13, 7), local(2026, 10, 16, 7)])
    }

    @Test func weeklyOnSaturdayAfterASnoozedDueDate() {
        // "Todos los sábados 8:00" con la fecha límite movida al sábado 10 a las 21:00.
        let rule = RepeatRule(frequency: .weekly, hour: 8, weekdays: [7])
        #expect(rule.nextOccurrence(after: local(2026, 10, 10, 21), calendar: mexico) == local(2026, 10, 17, 8))
    }

    @Test func weeklyWithSeveralDaysAndInterval() {
        let rule = RepeatRule(frequency: .weekly, interval: 2, hour: 9, weekdays: [2, 5]) // lunes y jueves
        let monday = local(2026, 10, 12, 9)
        #expect(rule.occurrences(after: monday, count: 3, calendar: mexico)
            == [local(2026, 10, 15, 9), local(2026, 10, 26, 9), local(2026, 10, 29, 9)])
    }

    @Test func monthlyClampsToShortMonths() {
        let rule = RepeatRule(frequency: .monthly, hour: 10, dayOfMonth: 31)
        #expect(rule.occurrences(after: local(2027, 1, 31, 10), count: 3, calendar: mexico)
            == [local(2027, 2, 28, 10), local(2027, 3, 31, 10), local(2027, 4, 30, 10)])
    }

    @Test func monthlyFromSnoozedDateGoesToRuleDay() {
        // "7mo de cada mes a las 20:00" con fecha límite 11 de octubre 21:00.
        let rule = RepeatRule(frequency: .monthly, hour: 20, dayOfMonth: 7)
        #expect(rule.nextOccurrence(after: local(2026, 10, 11, 21), calendar: mexico) == local(2026, 11, 7, 20))
        #expect(rule.nextOccurrence(after: local(2026, 10, 3, 9), calendar: mexico) == local(2026, 10, 7, 20))
    }

    @Test func everyTwoMonthsKeepsAlignment() {
        let rule = RepeatRule(frequency: .monthly, interval: 2, hour: 9, dayOfMonth: 1)
        #expect(rule.occurrences(after: local(2026, 12, 1, 9), count: 3, calendar: mexico)
            == [local(2027, 2, 1, 9), local(2027, 4, 1, 9), local(2027, 6, 1, 9)])
        // Completado tarde (en marzo): sigue la secuencia dic → feb → abr.
        #expect(rule.nextOccurrence(from: local(2026, 12, 1, 9), after: local(2027, 3, 15), calendar: mexico)
            == local(2027, 4, 1, 9))
    }

    @Test func lastDayOfMonth() {
        let rule = RepeatRule(frequency: .monthly, hour: 18, dayOfMonth: 31, lastDayOfMonth: true)
        #expect(rule.occurrences(after: local(2028, 1, 1), count: 3, calendar: mexico)
            == [local(2028, 1, 31, 18), local(2028, 2, 29, 18), local(2028, 3, 31, 18)])
    }

    @Test func lastSundayOfMonthIsSometimesTheFifthAndSometimesTheFourth() {
        let rule = RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -1, ordinalWeekday: 1)
        // Noviembre 2026 y enero 2027 tienen 5 domingos; diciembre y febrero, 4.
        #expect(rule.occurrences(after: local(2026, 11, 1), count: 4, calendar: mexico)
            == [local(2026, 11, 29, 9), local(2026, 12, 27, 9), local(2027, 1, 31, 9), local(2027, 2, 28, 9)])
    }

    @Test func nthWeekdayOfMonth() {
        // Segundo martes: 13 oct 2026, 10 nov, 8 dic.
        let second = RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: 2, ordinalWeekday: 3)
        #expect(second.occurrences(after: local(2026, 10, 1), count: 3, calendar: mexico)
            == [local(2026, 10, 13, 9), local(2026, 11, 10, 9), local(2026, 12, 8, 9)])
        // Primer jueves: octubre 2026 empieza en jueves.
        let first = RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: 1, ordinalWeekday: 5)
        #expect(first.nextOccurrence(after: local(2026, 9, 30), calendar: mexico) == local(2026, 10, 1, 9))
        // Cuarto sábado de cada 2 meses.
        let fourth = RepeatRule(frequency: .monthly, interval: 2, hour: 9, weekdayOrdinal: 4, ordinalWeekday: 7)
        #expect(fourth.occurrences(after: local(2026, 10, 1), count: 2, calendar: mexico)
            == [local(2026, 10, 24, 9), local(2026, 12, 26, 9)])
    }

    @Test func secondAndThirdToLast() {
        // Octubre 2026 tiene 5 sábados (3…31) y noviembre 4 (7…28).
        let penultimate = RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -2, ordinalWeekday: 7)
        #expect(penultimate.occurrences(after: local(2026, 10, 1), count: 2, calendar: mexico)
            == [local(2026, 10, 24, 9), local(2026, 11, 21, 9)])
        let antepenultimate = RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -3, ordinalWeekday: 7)
        #expect(antepenultimate.occurrences(after: local(2026, 10, 1), count: 2, calendar: mexico)
            == [local(2026, 10, 17, 9), local(2026, 11, 14, 9)])
    }

    @Test func weekdayPositionOfADate() {
        let tuesday = RepeatRule.weekdayPosition(of: local(2026, 10, 13), calendar: mexico)
        #expect(tuesday.ordinal == 2 && tuesday.weekday == 3)
        // 29 de noviembre de 2026 es el 5.º domingo: se toma como el último.
        let sunday = RepeatRule.weekdayPosition(of: local(2026, 11, 29), calendar: mexico)
        #expect(sunday.ordinal == -1 && sunday.weekday == 1)
    }

    @Test func ordinalNoteExplainsMonthsWithFourOrFive() {
        #expect(RepeatRule.ordinalNote(-1, weekday: 1)
            == "Algunos meses tienen 5 domingos y otros 4: el último domingo a veces es el 5.º y a veces el 4.º.")
        #expect(RepeatRule.ordinalNote(2, weekday: 1) == nil)
    }

    @Test func yearlyAndLeapDay() {
        let rule = RepeatRule(frequency: .yearly, hour: 20, minute: 20, dayOfMonth: 8, month: 11)
        #expect(rule.nextOccurrence(after: local(2026, 11, 8, 20, 20), calendar: mexico) == local(2027, 11, 8, 20, 20))
        #expect(rule.nextOccurrence(after: local(2026, 1, 1), calendar: mexico) == local(2026, 11, 8, 20, 20))

        let leap = RepeatRule(frequency: .yearly, hour: 9, dayOfMonth: 29, month: 2)
        #expect(leap.nextOccurrence(after: local(2028, 2, 29, 9), calendar: mexico) == local(2029, 2, 28, 9))
    }

    @Test func hourly() {
        let rule = RepeatRule(frequency: .hourly, interval: 2, minute: 15)
        #expect(rule.occurrences(after: local(2026, 10, 10, 9, 20), count: 2, calendar: mexico)
            == [local(2026, 10, 10, 11, 15), local(2026, 10, 10, 13, 15)])
    }

    @Test func emptyWeekdaysFallsBackToReferenceDay() {
        let rule = RepeatRule(frequency: .weekly, hour: 8)
        #expect(rule.nextOccurrence(after: local(2026, 10, 14, 9), calendar: mexico) == local(2026, 10, 21, 8))
    }

    @Test func matchingTakesValuesFromDate() {
        let rule = RepeatRule.matching(local(2026, 10, 17, 8, 45), frequency: .weekly, calendar: mexico)
        #expect(rule.weekdays == [7])
        #expect(rule.time == TimeOfDay(hour: 8, minute: 45))
        #expect(rule.dayOfMonth == 17)
        #expect(rule.month == 10)
    }

    @Test func codableRoundTripAndTolerantDecoding() throws {
        let rule = RepeatRule(frequency: .weekly, interval: 2, hour: 8, weekdays: [2, 6])
        let data = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(RepeatRule.self, from: data) == rule)

        let minimal = try JSONDecoder().decode(RepeatRule.self, from: Data(#"{"frequency":"daily","hour":7}"#.utf8))
        #expect(minimal == RepeatRule(frequency: .daily, hour: 7))

        let lastSunday = RepeatRule(frequency: .monthly, hour: 9, weekdayOrdinal: -1, ordinalWeekday: 1)
        #expect(try JSONDecoder().decode(RepeatRule.self, from: JSONEncoder().encode(lastSunday)) == lastSunday)
    }
}
