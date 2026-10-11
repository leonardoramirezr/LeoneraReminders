import Foundation

/// Un recordatorio: título, fecha límite (la ocurrencia actual) y, opcionalmente, una regla de repetición.
struct Reminder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    /// Fecha límite de la ocurrencia actual ("Fecha límite" en el CSV de Due).
    var dueDate: Date
    var repeatRule: RepeatRule?
    /// Si se pospuso, la alarma suena a esta hora en lugar de `dueDate`.
    var snoozedUntil: Date?
    /// Sólo los recordatorios sin repetición quedan completados; los repetitivos avanzan a la siguiente fecha.
    var completedAt: Date?
    var lastCompletedAt: Date?
    var createdAt: Date
    /// Alarma de AlarmKit programada actualmente para este recordatorio.
    var scheduledAlarm: ScheduledAlarm?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        repeatRule: RepeatRule? = nil,
        snoozedUntil: Date? = nil,
        completedAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        createdAt: Date = Date(),
        scheduledAlarm: ScheduledAlarm? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.repeatRule = repeatRule
        self.snoozedUntil = snoozedUntil
        self.completedAt = completedAt
        self.lastCompletedAt = lastCompletedAt
        self.createdAt = createdAt
        self.scheduledAlarm = scheduledAlarm
    }

    var isCompleted: Bool { completedAt != nil }

    /// Momento en que debe sonar la alarma.
    var alertDate: Date { snoozedUntil ?? dueDate }

    func isOverdue(now: Date = Date()) -> Bool {
        !isCompleted && alertDate <= now
    }

    /// Marca la ocurrencia actual como completada. Si se repite, avanza a la siguiente ocurrencia
    /// posterior a `now`; si no, queda completado.
    mutating func complete(now: Date = Date(), calendar: Calendar = .current) {
        snoozedUntil = nil
        lastCompletedAt = now
        if let rule = repeatRule,
           let next = rule.nextOccurrence(from: dueDate, after: now, calendar: calendar) {
            dueDate = next
        } else {
            completedAt = now
        }
    }

    /// Hace que la alarma vuelva a sonar dentro de `amount`.
    mutating func snooze(by amount: TimeAmount, now: Date = Date(), calendar: Calendar = .current) {
        snoozedUntil = amount.added(to: now, calendar: calendar)
    }

    /// Cambia la fecha límite (anula cualquier posposición).
    mutating func reschedule(to date: Date) {
        dueDate = date
        snoozedUntil = nil
        completedAt = nil
    }

    mutating func markIncomplete() {
        completedAt = nil
    }

    /// Para recordatorios repetitivos cuya fecha ya pasó: mueve la fecha a la siguiente ocurrencia futura.
    /// Devuelve `true` si cambió algo.
    @discardableResult
    mutating func advancePastDueRepetition(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let rule = repeatRule, alertDate <= now,
              let next = rule.nextOccurrence(from: dueDate, after: now, calendar: calendar)
        else { return false }
        dueDate = next
        snoozedUntil = nil
        return true
    }
}

/// Registro de la alarma que se programó en AlarmKit, para saber si hay que reprogramarla.
struct ScheduledAlarm: Codable, Hashable, Sendable {
    var id: UUID
    var fireDate: Date
    /// Resume el contenido de la alarma (título y botones); si cambia, se reprograma.
    var signature: String
}

extension Reminder {
    private enum CodingKeys: String, CodingKey {
        case id, title, dueDate, repeatRule, snoozedUntil, completedAt, lastCompletedAt, createdAt, scheduledAlarm
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            dueDate: try c.decode(Date.self, forKey: .dueDate),
            repeatRule: try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule),
            snoozedUntil: try c.decodeIfPresent(Date.self, forKey: .snoozedUntil),
            completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt),
            lastCompletedAt: try c.decodeIfPresent(Date.self, forKey: .lastCompletedAt),
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            scheduledAlarm: try c.decodeIfPresent(ScheduledAlarm.self, forKey: .scheduledAlarm)
        )
    }
}
