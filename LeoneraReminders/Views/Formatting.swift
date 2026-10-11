import Foundation

/// Textos de fecha para la interfaz.
enum DateText {
    /// "Hoy, 21:00", "Mañana, 8:00", "sáb 17 oct, 10:00" o "1 feb 2027, 13:00".
    static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Hoy, \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Mañana, \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Ayer, \(time)"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = sameYear
            ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(day), \(time)"
    }

    /// "sábado, 17 de octubre de 2026, 10:00"
    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Qué recordatorio se edita en la hoja del editor.
enum EditorTarget: Identifiable, Hashable {
    case new
    case edit(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let id): id.uuidString
        }
    }

    var reminderID: UUID? {
        if case .edit(let id) = self { return id }
        return nil
    }
}

/// Envoltorio para presentar hojas a partir de un id de recordatorio.
struct ReminderSheetID: Identifiable, Hashable {
    let id: UUID
}
