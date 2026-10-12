import Foundation

/// Un recordatorio: título, fecha límite (la ocurrencia actual) y, opcionalmente, una regla de repetición.
struct Reminder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    /// Fecha límite de la ocurrencia actual ("Fecha límite" en el CSV de Due); la alarma suena a esta hora.
    /// Posponer la mueve.
    var dueDate: Date
    var repeatRule: RepeatRule?
    /// Vencido sin atender: sus alarmas vuelven a empezar a esta hora (sigue contando como vencido).
    var retryFrom: Date?
    /// Sólo los recordatorios sin repetición quedan completados; los repetitivos avanzan a la siguiente fecha.
    var completedAt: Date?
    var lastCompletedAt: Date?
    var createdAt: Date
    /// Alarmas de AlarmKit programadas ahora: la principal y las que repiten el aviso si no se atiende.
    var scheduledAlarms: [ScheduledAlarm]

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        repeatRule: RepeatRule? = nil,
        retryFrom: Date? = nil,
        completedAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        createdAt: Date = Date(),
        scheduledAlarms: [ScheduledAlarm] = []
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.repeatRule = repeatRule
        self.retryFrom = retryFrom
        self.completedAt = completedAt
        self.lastCompletedAt = lastCompletedAt
        self.createdAt = createdAt
        self.scheduledAlarms = scheduledAlarms
    }

    var isCompleted: Bool { completedAt != nil }

    func isOverdue(now: Date = Date()) -> Bool {
        !isCompleted && dueDate <= now
    }

    /// Marca la ocurrencia actual como completada. Si se repite, avanza a la siguiente ocurrencia
    /// posterior a `now`; si no, queda completado.
    mutating func complete(now: Date = Date(), calendar: Calendar = .current) {
        retryFrom = nil
        lastCompletedAt = now
        if let rule = repeatRule,
           let next = rule.nextOccurrence(from: dueDate, after: now, calendar: calendar) {
            dueDate = next
        } else {
            completedAt = now
        }
    }

    /// Pospone: la fecha límite pasa a dentro de `amount` (contando desde ahora) y ahí vuelve a sonar.
    mutating func snooze(by amount: TimeAmount, now: Date = Date(), calendar: Calendar = .current) {
        dueDate = amount.added(to: now, calendar: calendar)
        retryFrom = nil
    }

    /// Cambia la fecha límite.
    mutating func reschedule(to date: Date) {
        dueDate = date
        retryFrom = nil
        completedAt = nil
    }

    mutating func markIncomplete() {
        completedAt = nil
    }

    /// Momentos futuros (posteriores a `now`) en que deben sonar sus alarmas: la hora del aviso y, si se ignora,
    /// cada `followUp.interval` después, hasta `followUp.count` veces. Si ya pasó la hora, sólo quedan las repeticiones.
    func pendingAlarmDates(after now: Date, followUp: FollowUpSettings, calendar: Calendar = .current) -> [Date] {
        guard !isCompleted else { return [] }
        let start = retryFrom.map { max($0, dueDate) } ?? dueDate
        var dates = [start]
        if followUp.isEnabled, followUp.count > 0 {
            for k in 1...followUp.count {
                let step = TimeAmount(followUp.interval.value * k, followUp.interval.unit)
                dates.append(step.added(to: start, calendar: calendar))
            }
        }
        return dates.filter { $0 > now }
    }

    /// Si está vencido y no tiene una alarma a más tardar en el siguiente minuto, hace que vuelva a sonar
    /// al empezar el siguiente minuto (y desde ahí, las repeticiones). Devuelve `true` si cambió algo.
    @discardableResult
    mutating func retryIfOverdue(now: Date = Date(), followUp: FollowUpSettings, calendar: Calendar = .current) -> Bool {
        guard isOverdue(now: now) else { return false }
        let nextMinute = calendar.dateInterval(of: .minute, for: now)?.end ?? now.addingTimeInterval(60)
        if let next = pendingAlarmDates(after: now, followUp: followUp, calendar: calendar).first, next <= nextMinute {
            return false
        }
        retryFrom = nextMinute
        return true
    }

    /// Para recordatorios repetitivos cuya fecha ya pasó: mueve la fecha a la siguiente ocurrencia futura.
    /// Devuelve `true` si cambió algo.
    @discardableResult
    mutating func advancePastDueRepetition(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let rule = repeatRule, dueDate <= now,
              let next = rule.nextOccurrence(from: dueDate, after: now, calendar: calendar)
        else { return false }
        dueDate = next
        retryFrom = nil
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
        case id, title, dueDate, repeatRule, retryFrom, completedAt, lastCompletedAt, createdAt, scheduledAlarms
        /// Versiones anteriores guardaban una sola alarma.
        case scheduledAlarm
        /// Versiones anteriores posponían sin mover la fecha límite; al leerlas, la fecha límite pasa a ser esa hora.
        case snoozedUntil
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            dueDate: try c.decodeIfPresent(Date.self, forKey: .snoozedUntil) ?? c.decode(Date.self, forKey: .dueDate),
            repeatRule: try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule),
            retryFrom: try c.decodeIfPresent(Date.self, forKey: .retryFrom),
            completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt),
            lastCompletedAt: try c.decodeIfPresent(Date.self, forKey: .lastCompletedAt),
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            scheduledAlarms: try c.decodeIfPresent([ScheduledAlarm].self, forKey: .scheduledAlarms)
                ?? (try c.decodeIfPresent(ScheduledAlarm.self, forKey: .scheduledAlarm)).map { [$0] } ?? []
        )
    }
}

extension Reminder {
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encodeIfPresent(repeatRule, forKey: .repeatRule)
        try c.encodeIfPresent(retryFrom, forKey: .retryFrom)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(lastCompletedAt, forKey: .lastCompletedAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(scheduledAlarms, forKey: .scheduledAlarms)
    }
}
