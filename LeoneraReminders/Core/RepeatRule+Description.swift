import Foundation

/// Nombres en español usados en las descripciones (independientes del idioma del dispositivo).
enum SpanishNames {
    /// Índice = weekday de `Calendar` (1 = domingo).
    static let weekdays = ["", "domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    static let weekdaysPlural = ["", "domingos", "lunes", "martes", "miércoles", "jueves", "viernes", "sábados"]
    static let weekdayInitials = ["", "D", "L", "M", "X", "J", "V", "S"]
    /// Índice = mes (1 = enero).
    static let months = ["", "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                         "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    /// Une una lista con comas y "y": "lunes, miércoles y viernes".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " y " + items[items.count - 1]
        }
    }

    /// Días de la semana en el orden del calendario (empezando por `firstWeekday`).
    static func orderedWeekdays(calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

extension RepeatRule {
    static let workdays: Set<Int> = [2, 3, 4, 5, 6]
    static let weekendDays: Set<Int> = [1, 7]

    /// Descripción corta en español, p. ej. "Todos los sábados 8:00" o "Día 7 de cada mes a las 20:00".
    func summary(calendar: Calendar = .current) -> String {
        let timeLabel = time.label
        switch frequency {
        case .hourly:
            let every = interval == 1 ? "Cada hora" : "Cada \(interval) horas"
            return minute == 0 ? "\(every) en punto" : "\(every), al minuto \(minute)"

        case .daily:
            return interval == 1 ? "Diariamente \(timeLabel)" : "Cada \(interval) días \(timeLabel)"

        case .weekly:
            let ordered = SpanishNames.orderedWeekdays(calendar: calendar).filter { weekdays.contains($0) }
            let names = SpanishNames.list(ordered.map { SpanishNames.weekdaysPlural[$0] })
            if interval == 1 {
                switch weekdays {
                case Self.workdays: return "Entre semana \(timeLabel)"
                case Self.weekendDays: return "Fines de semana \(timeLabel)"
                case _ where ordered.count == 7: return "Diariamente \(timeLabel)"
                case _ where ordered.isEmpty: return "Cada semana \(timeLabel)"
                default: return "Todos los \(names) \(timeLabel)"
                }
            }
            return ordered.isEmpty
                ? "Cada \(interval) semanas \(timeLabel)"
                : "Cada \(interval) semanas: \(names) \(timeLabel)"

        case .monthly:
            let day = weekdayOrdinal != 0
                ? "\(Self.ordinalAdjective(weekdayOrdinal)) \(SpanishNames.weekdays[ordinalWeekday])"
                : lastDayOfMonth ? "Último día" : "Día \(dayOfMonth)"
            let every = interval == 1 ? "de cada mes" : "de cada \(interval) meses"
            return "\(day) \(every) a las \(timeLabel)"

        case .yearly:
            let date = "el \(dayOfMonth) de \(SpanishNames.months[month])"
            let every = interval == 1 ? "Cada año" : "Cada \(interval) años"
            return "\(every) \(date), \(timeLabel)"
        }
    }

    /// "Primer", "Segundo", …, "Último", "Penúltimo", "Antepenúltimo" (antes de un día de la semana).
    static func ordinalAdjective(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: "Primer"
        case 2: "Segundo"
        case 3: "Tercer"
        case 4: "Cuarto"
        case -1: "Último"
        case -2: "Penúltimo"
        case -3: "Antepenúltimo"
        default: ""
        }
    }

    /// Opción del selector "Cuál": "El primero", …, "El último (4.º o 5.º)".
    static func ordinalOption(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: "El primero"
        case 2: "El segundo"
        case 3: "El tercero"
        case 4: "El cuarto"
        case -1: "El último (4.º o 5.º)"
        case -2: "El penúltimo (3.º o 4.º)"
        case -3: "El antepenúltimo (2.º o 3.º)"
        default: ""
        }
    }

    /// Aclaración para las posiciones contadas desde el final, p. ej. "Algunos meses tienen 5 domingos y otros 4:
    /// el último domingo a veces es el 5.º y a veces el 4.º."; `nil` para primero…cuarto.
    static func ordinalNote(_ ordinal: Int, weekday: Int) -> String? {
        guard (-3 ... -1).contains(ordinal) else { return nil }
        let name = SpanishNames.weekdays[weekday]
        let plural = SpanishNames.weekdaysPlural[weekday]
        let position = ordinalAdjective(ordinal).lowercased()
        return "Algunos meses tienen 5 \(plural) y otros 4: el \(position) \(name) a veces es el \(6 + ordinal).º y a veces el \(5 + ordinal).º."
    }

    /// Nombre de la unidad para el selector "Cada N …".
    func unitName(for value: Int) -> String {
        switch frequency {
        case .hourly: value == 1 ? "hora" : "horas"
        case .daily: value == 1 ? "día" : "días"
        case .weekly: value == 1 ? "semana" : "semanas"
        case .monthly: value == 1 ? "mes" : "meses"
        case .yearly: value == 1 ? "año" : "años"
        }
    }
}

extension RepeatRule.Frequency {
    var label: String {
        switch self {
        case .hourly: "Cada hora"
        case .daily: "Diario"
        case .weekly: "Semanal"
        case .monthly: "Mensual"
        case .yearly: "Anual"
        }
    }
}
