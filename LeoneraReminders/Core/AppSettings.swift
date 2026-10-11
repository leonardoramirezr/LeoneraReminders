import Foundation

/// Qué hace un botón de la alarma cuando suena.
///
/// Ninguno completa el recordatorio: completar se hace en la app deslizando un control, para que un toque
/// rápido (como «Detener») no lo marque por error.
enum AlarmAction: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Vuelve a sonar dentro del tiempo de "posponer por defecto".
    case snooze
    /// Pospone por defecto y abre la app para completar (deslizando) o elegir otro tiempo.
    case snoozeOptions
    /// Sin botón (sólo para el botón secundario).
    case none

    var id: String { rawValue }
}

/// Matriz de ajuste rápido de la fecha límite (3 filas):
/// la primera fija una hora, la segunda suma y la tercera resta.
struct QuickAdjustGrid: Codable, Hashable, Sendable {
    var times: [TimeOfDay]
    var additions: [TimeAmount]
    var subtractions: [TimeAmount]

    static let columnCount = 4

    static let `default` = QuickAdjustGrid(
        times: [TimeOfDay(hour: 10), TimeOfDay(hour: 14), TimeOfDay(hour: 18), TimeOfDay(hour: 21)],
        additions: [.minutes(10), .hours(1), .days(1), .weeks(1)],
        subtractions: [.minutes(10), .hours(1), .days(1), .weeks(1)]
    )

    enum Cell: Hashable, Sendable {
        case setTime(TimeOfDay)
        case add(TimeAmount)
        case subtract(TimeAmount)
    }

    /// Filas de la matriz, siempre con `columnCount` columnas.
    var rows: [[Cell]] {
        [
            Self.padded(times, with: Self.default.times).map(Cell.setTime),
            Self.padded(additions, with: Self.default.additions).map(Cell.add),
            Self.padded(subtractions, with: Self.default.subtractions).map(Cell.subtract),
        ]
    }

    /// Cambia la celda de la columna `column` en la fila que corresponde al tipo de celda.
    mutating func setCell(_ cell: Cell, column: Int) {
        guard (0..<Self.columnCount).contains(column) else { return }
        times = Self.padded(times, with: Self.default.times)
        additions = Self.padded(additions, with: Self.default.additions)
        subtractions = Self.padded(subtractions, with: Self.default.subtractions)
        switch cell {
        case .setTime(let time): times[column] = time
        case .add(let amount): additions[column] = amount
        case .subtract(let amount): subtractions[column] = amount
        }
    }

    private static func padded<T>(_ values: [T], with defaults: [T]) -> [T] {
        (0..<columnCount).map { $0 < values.count ? values[$0] : defaults[$0] }
    }
}

extension QuickAdjustGrid.Cell {
    func apply(to date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .setTime(let time): time.applied(to: date, calendar: calendar)
        case .add(let amount): amount.added(to: date, calendar: calendar)
        case .subtract(let amount): amount.subtracted(from: date, calendar: calendar)
        }
    }

    /// Texto principal y unidad, p. ej. ("+10", "min") o ("10:00", "").
    var labelParts: (value: String, unit: String) {
        switch self {
        case .setTime(let time): (time.label, "")
        case .add(let amount): ("+\(amount.value)", amount.unit.shortName(for: amount.value))
        case .subtract(let amount): ("−\(amount.value)", amount.unit.shortName(for: amount.value))
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .setTime(let time): "Cambiar la hora a las \(time.label)"
        case .add(let amount): "Sumar \(amount.longLabel)"
        case .subtract(let amount): "Restar \(amount.longLabel)"
        }
    }
}

/// Repetir la alarma si no se atiende: vuelve a sonar cada `interval`, hasta `count` veces.
struct FollowUpSettings: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var interval: TimeAmount
    var count: Int

    static let `default` = FollowUpSettings(isEnabled: true, interval: .minutes(1), count: 10)
    static let intervalOptions: [TimeAmount] = [.minutes(1), .minutes(2), .minutes(5), .minutes(10), .minutes(15), .minutes(30), .hours(1)]
    static let countOptions = [3, 5, 10, 15, 20, 30]
}

/// Configuración de la app.
struct AppSettings: Codable, Hashable, Sendable {
    /// Opciones de "Recordar en…" que se ofrecen al posponer.
    var snoozeOptions: [TimeAmount]
    /// La opción que usa el botón de la alarma.
    var defaultSnooze: TimeAmount
    /// Acción al detener la alarma (en iOS 26.1+ el botón Detener lo dibuja el sistema).
    var stopAction: AlarmAction
    /// Acción del segundo botón de la alarma.
    var secondaryAction: AlarmAction
    var quickAdjustGrid: QuickAdjustGrid
    /// Volver a sonar si la alarma se ignora.
    var followUp: FollowUpSettings = .default

    static let defaultSnoozeOptions: [TimeAmount] = [
        .minutes(1), .minutes(5), .minutes(10), .minutes(20), .minutes(40), .minutes(60), .hours(2), .hours(3),
    ]

    static let `default` = AppSettings(
        snoozeOptions: defaultSnoozeOptions,
        defaultSnooze: .minutes(10),
        stopAction: .snooze,
        secondaryAction: .snoozeOptions,
        quickAdjustGrid: .default,
        followUp: .default
    )

    /// Opciones ordenadas y sin repetir.
    var sortedSnoozeOptions: [TimeAmount] {
        var seen = Set<TimeAmount>()
        return snoozeOptions.sorted().filter { seen.insert($0).inserted }
    }

    /// Cambia si cambia algo de lo que se muestra o hace la alarma; sirve para saber si hay que reprogramarla.
    var alarmSignature: String {
        "\(stopAction.rawValue)|\(secondaryAction.rawValue)|\(defaultSnooze.id)"
    }
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case snoozeOptions, defaultSnooze, stopAction, secondaryAction, quickAdjustGrid, followUp
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        self.init(
            snoozeOptions: (try? c.decodeIfPresent([TimeAmount].self, forKey: .snoozeOptions)) ?? fallback.snoozeOptions,
            defaultSnooze: (try? c.decodeIfPresent(TimeAmount.self, forKey: .defaultSnooze)) ?? fallback.defaultSnooze,
            stopAction: (try? c.decodeIfPresent(AlarmAction.self, forKey: .stopAction)) ?? fallback.stopAction,
            secondaryAction: (try? c.decodeIfPresent(AlarmAction.self, forKey: .secondaryAction)) ?? fallback.secondaryAction,
            quickAdjustGrid: (try? c.decodeIfPresent(QuickAdjustGrid.self, forKey: .quickAdjustGrid)) ?? fallback.quickAdjustGrid,
            followUp: (try? c.decodeIfPresent(FollowUpSettings.self, forKey: .followUp)) ?? fallback.followUp
        )
    }
}
