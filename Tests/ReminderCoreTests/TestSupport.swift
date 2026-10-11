import Foundation
import Testing
@testable import ReminderCore

/// Calendario fijo para que las pruebas no dependan de la zona horaria de la máquina.
let mexico: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
    calendar.locale = Locale(identifier: "es_MX")
    calendar.firstWeekday = 1
    return calendar
}()

/// Fecha local en `mexico`.
func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    mexico.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
}

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}
