import Foundation

/// Escribe los recordatorios en un CSV con las mismas columnas que exporta Due ("Recordatorio", "Fecha límite",
/// "Repetir") más "Completado", así `ReminderCSVImporter` (y la misma app) lo puede volver a leer.
enum ReminderCSVExporter {
    static let header = ["Recordatorio", "Fecha límite", "Repetir", "Completado"]

    /// Texto CSV (RFC 4180): todos los campos entre comillas y filas separadas por CRLF.
    /// Las fechas van en ISO 8601 (UTC) y la repetición con el mismo resumen que muestra la app,
    /// que `DueRepeatParser` entiende.
    static func csv(for reminders: [Reminder], calendar: Calendar = .current) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let rows = reminders.map { reminder in
            [
                reminder.title,
                iso.string(from: reminder.dueDate),
                reminder.repeatRule?.summary(calendar: calendar) ?? "",
                reminder.completedAt.map(iso.string(from:)) ?? "",
            ]
        }
        return ([header] + rows)
            .map { $0.map(quote).joined(separator: ",") + "\r\n" }
            .joined()
    }

    /// Archivo UTF-8 con BOM para que Excel y Numbers respeten acentos y emoji.
    static func data(for reminders: [Reminder], calendar: Calendar = .current) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(csv(for: reminders, calendar: calendar).utf8)
    }

    /// Nombre sugerido sin extensión, p. ej. "Recordatorios 2026-10-13".
    static func fileName(date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "Recordatorios %04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func quote(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
