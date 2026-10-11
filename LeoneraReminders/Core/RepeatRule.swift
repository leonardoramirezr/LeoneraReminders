import Foundation

/// Regla de repetición de un recordatorio.
///
/// Cubre las formas que aparecen en la exportación de Due:
/// "Diariamente 23:00", "Todos los sábados 8:00", "7mo de cada mes a las 20:00",
/// "1er de cada 2 meses a las 9:00" y "Todos los 8 nov, 20:20"; además de cada N horas,
/// varios días de la semana y el último día del mes.
///
/// La regla guarda su propia hora/día; la fecha límite del recordatorio es sólo la ocurrencia
/// actual (que puede haberse movido o pospuesto) y no altera la regla.
struct RepeatRule: Codable, Hashable, Sendable {
    enum Frequency: String, Codable, CaseIterable, Sendable, Identifiable {
        case hourly, daily, weekly, monthly, yearly
        var id: String { rawValue }
    }

    var frequency: Frequency
    /// Cada cuántas unidades se repite (1 = cada hora/día/semana/mes/año).
    var interval: Int
    /// Hora del día (no se usa en `.hourly`).
    var hour: Int
    /// Minuto (en `.hourly` es el minuto de cada hora).
    var minute: Int
    /// Días de la semana para `.weekly`, con la numeración de `Calendar` (1 = domingo … 7 = sábado).
    var weekdays: Set<Int>
    /// Día del mes para `.monthly` y `.yearly` (1…31; se ajusta a la duración del mes).
    var dayOfMonth: Int
    /// `.monthly`: el último día de cada mes en lugar de `dayOfMonth`.
    var lastDayOfMonth: Bool
    /// Mes (1…12) para `.yearly`.
    var month: Int

    init(
        frequency: Frequency,
        interval: Int = 1,
        hour: Int = 9,
        minute: Int = 0,
        weekdays: Set<Int> = [],
        dayOfMonth: Int = 1,
        lastDayOfMonth: Bool = false,
        month: Int = 1
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        self.lastDayOfMonth = lastDayOfMonth
        self.month = min(max(month, 1), 12)
    }

    /// Crea una regla cuyos valores (hora, día de la semana, día del mes, mes) salen de `date`.
    static func matching(_ date: Date, frequency: Frequency, interval: Int = 1, calendar: Calendar = .current) -> RepeatRule {
        let parts = calendar.dateComponents([.hour, .minute, .weekday, .day, .month], from: date)
        return RepeatRule(
            frequency: frequency,
            interval: interval,
            hour: parts.hour ?? 9,
            minute: parts.minute ?? 0,
            weekdays: [parts.weekday ?? 1],
            dayOfMonth: parts.day ?? 1,
            month: parts.month ?? 1
        )
    }

    var time: TimeOfDay {
        get { TimeOfDay(hour: hour, minute: minute) }
        set { hour = newValue.hour; minute = newValue.minute }
    }

    /// Días efectivos de la semana; si no hay ninguno se usa el de `reference`.
    func effectiveWeekdays(reference: Date, calendar: Calendar) -> Set<Int> {
        weekdays.isEmpty ? [calendar.component(.weekday, from: reference)] : weekdays
    }
}

// MARK: - Cálculo de ocurrencias

extension RepeatRule {
    /// La primera ocurrencia estrictamente posterior a `date`.
    ///
    /// Los periodos (hora, día, semana, mes, año) se cuentan desde el periodo que contiene `date`,
    /// así "cada 2 meses" alterna meses tomando como referencia la ocurrencia actual.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        let step = max(1, interval)
        switch frequency {
        case .hourly:
            guard let hourStart = calendar.dateInterval(of: .hour, for: date)?.start else { return nil }
            for k in 0...2 {
                let candidate = hourStart.addingTimeInterval(TimeInterval(k * step * 3_600 + minute * 60))
                if candidate > date { return candidate }
            }
            return nil

        case .daily:
            let dayStart = calendar.startOfDay(for: date)
            for k in 0...2 {
                guard let day = calendar.date(byAdding: .day, value: k * step, to: dayStart),
                      let candidate = Self.date(onDayOf: day, hour: hour, minute: minute, calendar: calendar)
                else { continue }
                if candidate > date { return candidate }
            }
            return nil

        case .weekly:
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return nil }
            let days = effectiveWeekdays(reference: date, calendar: calendar)
            for k in 0...2 {
                guard let start = calendar.date(byAdding: .weekOfYear, value: k * step, to: weekStart) else { continue }
                for offset in 0..<7 {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                          days.contains(calendar.component(.weekday, from: day)),
                          let candidate = Self.date(onDayOf: day, hour: hour, minute: minute, calendar: calendar)
                    else { continue }
                    if candidate > date { return candidate }
                }
            }
            return nil

        case .monthly:
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let monthValue = parts.month,
                  let monthStart = calendar.date(from: DateComponents(year: year, month: monthValue, day: 1))
            else { return nil }
            for k in 0...3 {
                guard let target = calendar.date(byAdding: .month, value: k * step, to: monthStart) else { continue }
                let targetParts = calendar.dateComponents([.year, .month], from: target)
                guard let y = targetParts.year, let m = targetParts.month else { continue }
                let length = Self.daysIn(year: y, month: m, calendar: calendar)
                let day = lastDayOfMonth ? length : min(dayOfMonth, length)
                guard let candidate = Self.date(year: y, month: m, day: day, hour: hour, minute: minute, calendar: calendar)
                else { continue }
                if candidate > date { return candidate }
            }
            return nil

        case .yearly:
            guard let year = calendar.dateComponents([.year], from: date).year else { return nil }
            for k in 0...2 {
                let y = year + k * step
                let day = min(dayOfMonth, Self.daysIn(year: y, month: month, calendar: calendar))
                guard let candidate = Self.date(year: y, month: month, day: day, hour: hour, minute: minute, calendar: calendar)
                else { continue }
                if candidate > date { return candidate }
            }
            return nil
        }
    }

    /// La primera ocurrencia en o después de `date`.
    func firstOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        nextOccurrence(after: date.addingTimeInterval(-1), calendar: calendar)
    }

    /// Las siguientes `count` ocurrencias después de `date`.
    func occurrences(after date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var cursor = date
        while result.count < count, let next = nextOccurrence(after: cursor, calendar: calendar) {
            result.append(next)
            cursor = next
        }
        return result
    }

    /// Avanza desde la ocurrencia `from` hasta la primera posterior a `now`, respetando la alineación
    /// del intervalo (p. ej. "cada 2 meses" sigue contando desde `from`).
    func nextOccurrence(from occurrence: Date, after now: Date, calendar: Calendar = .current) -> Date? {
        var cursor = occurrence
        for _ in 0..<100_000 {
            guard let next = nextOccurrence(after: cursor, calendar: calendar) else { return nil }
            if next > now { return next }
            cursor = next
        }
        return nextOccurrence(after: now, calendar: calendar)
    }

    static func daysIn(year: Int, month: Int, calendar: Calendar) -> Int {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 28 }
        return range.count
    }

    static func date(onDayOf day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return date(year: y, month: m, day: d, hour: hour, minute: minute, calendar: calendar)
    }

    static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: 0))
    }
}

// MARK: - Decodificación tolerante

extension RepeatRule {
    private enum CodingKeys: String, CodingKey {
        case frequency, interval, hour, minute, weekdays, dayOfMonth, lastDayOfMonth, month
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            frequency: try c.decode(Frequency.self, forKey: .frequency),
            interval: try c.decodeIfPresent(Int.self, forKey: .interval) ?? 1,
            hour: try c.decodeIfPresent(Int.self, forKey: .hour) ?? 9,
            minute: try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0,
            weekdays: try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? [],
            dayOfMonth: try c.decodeIfPresent(Int.self, forKey: .dayOfMonth) ?? 1,
            lastDayOfMonth: try c.decodeIfPresent(Bool.self, forKey: .lastDayOfMonth) ?? false,
            month: try c.decodeIfPresent(Int.self, forKey: .month) ?? 1
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(interval, forKey: .interval)
        try c.encode(hour, forKey: .hour)
        try c.encode(minute, forKey: .minute)
        try c.encode(weekdays.sorted(), forKey: .weekdays)
        try c.encode(dayOfMonth, forKey: .dayOfMonth)
        try c.encode(lastDayOfMonth, forKey: .lastDayOfMonth)
        try c.encode(month, forKey: .month)
    }
}
