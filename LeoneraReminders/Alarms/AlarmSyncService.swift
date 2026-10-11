import AlarmKit
import AppIntents
import Foundation
import Observation
import SwiftUI
import os

/// Mantiene una alarma de AlarmKit por cada recordatorio pendiente, a la hora en que debe sonar.
///
/// Cada alarma es de fecha fija (`.fixed`): las repeticiones (mensual, anual, cada N…) las calcula la app
/// y, al completar o posponer, se programa la siguiente alarma.
@MainActor
@Observable
final class AlarmSyncService {
    static let shared = AlarmSyncService()

    private(set) var authorizationState: AlarmManager.AuthorizationState
    /// Alarmas que están sonando ahora.
    private(set) var alertingAlarmIDs: Set<UUID> = []
    /// AlarmKit rechazó más alarmas; las más lejanas quedan sin programar hasta que se liberen.
    private(set) var limitReached = false
    private(set) var lastError: String?

    private let manager = AlarmManager.shared
    private let logger = Logger(subsystem: "LeoneraReminders", category: "alarms")
    @ObservationIgnored private var lastSync: Task<Void, Never>?
    @ObservationIgnored private var pendingRequest: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false

    private init() {
        authorizationState = AlarmManager.shared.authorizationState
    }

    /// Empieza a observar permisos y alarmas, pide permiso la primera vez y sincroniza.
    func start() async {
        if !isObserving {
            isObserving = true
            Task {
                for await state in manager.authorizationUpdates {
                    authorizationState = state
                    if state == .authorized { requestSync() }
                }
            }
            Task {
                for await alarms in manager.alarmUpdates {
                    alertingAlarmIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
                }
            }
        }
        if manager.authorizationState == .notDetermined {
            await requestAuthorization()
        }
        await syncNow()
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            authorizationState = try await manager.requestAuthorization()
        } catch {
            logger.error("Permiso de alarmas: \(error.localizedDescription, privacy: .public)")
            authorizationState = manager.authorizationState
        }
        return authorizationState == .authorized
    }

    /// Sincroniza en breve, agrupando cambios seguidos.
    func requestSync() {
        pendingRequest?.cancel()
        pendingRequest = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    /// Sincroniza ya y espera a que termine (las sincronizaciones nunca corren en paralelo).
    func syncNow() async {
        let previous = lastSync
        let task = Task {
            await previous?.value
            await performSync()
        }
        lastSync = task
        await task.value
    }

    // MARK: - Sincronización

    private func performSync() async {
        authorizationState = manager.authorizationState
        guard authorizationState == .authorized else { return }

        let existing: [Alarm]
        do {
            existing = try manager.alarms
        } catch {
            lastError = error.localizedDescription
            logger.error("No se pudieron leer las alarmas: \(error.localizedDescription, privacy: .public)")
            return
        }
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let store = ReminderStore.shared
        let settings = SettingsStore.shared.settings
        let now = Date()

        var keep = Set<UUID>()
        var pending: [Reminder] = []
        for reminder in store.reminders where !reminder.isCompleted {
            if let current = reminder.scheduledAlarm, let alarm = existingByID[current.id] {
                let upToDate = current.fireDate == reminder.alertDate
                    && current.signature == signature(for: reminder, settings: settings)
                // Si está sonando y el recordatorio no ha cambiado de hora, se deja sonar.
                let ringing = alarm.state == .alerting && reminder.alertDate <= now
                if upToDate || ringing {
                    keep.insert(current.id)
                    continue
                }
            }
            if reminder.alertDate > now.addingTimeInterval(1) {
                pending.append(reminder)
            } else if reminder.scheduledAlarm != nil {
                store.setScheduledAlarm(nil, for: reminder.id)
            }
        }

        // Primero se quitan las que sobran, para no chocar con el límite de alarmas.
        for alarm in existing where !keep.contains(alarm.id) {
            try? manager.cancel(id: alarm.id)
        }

        var reachedLimit = false
        lastError = nil
        for reminder in pending.sorted(by: { $0.alertDate < $1.alertDate }) {
            guard !reachedLimit else {
                store.setScheduledAlarm(nil, for: reminder.id)
                continue
            }
            let alarmID = UUID()
            do {
                let configuration = Self.configuration(for: reminder, alarmID: alarmID, settings: settings)
                _ = try await manager.schedule(id: alarmID, configuration: configuration)
                let record = ScheduledAlarm(id: alarmID, fireDate: reminder.alertDate, signature: signature(for: reminder, settings: settings))
                store.setScheduledAlarm(record, for: reminder.id)
            } catch AlarmManager.AlarmError.maximumLimitReached {
                reachedLimit = true
                store.setScheduledAlarm(nil, for: reminder.id)
            } catch {
                lastError = error.localizedDescription
                logger.error("No se pudo programar «\(reminder.title, privacy: .private)»: \(error.localizedDescription, privacy: .public)")
                store.setScheduledAlarm(nil, for: reminder.id)
            }
        }
        limitReached = reachedLimit
    }

    private func signature(for reminder: Reminder, settings: AppSettings) -> String {
        "\(reminder.title)|\(settings.alarmSignature)"
    }

    // MARK: - Configuración de la alarma

    nonisolated private static func configuration(
        for reminder: Reminder,
        alarmID: UUID,
        settings: AppSettings
    ) -> AlarmManager.AlarmConfiguration<ReminderAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: reminder.title)
        let secondaryButton = button(for: settings.secondaryAction, settings: settings)
        let secondaryBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = secondaryButton == nil ? nil : .custom

        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            // Desde iOS 26.1 el control de detener lo dibuja el sistema; su acción es `stopIntent`.
            alert = AlarmPresentation.Alert(
                title: title,
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryBehavior
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: button(for: settings.stopAction, settings: settings)
                    ?? AlarmButton(text: "Detener", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryBehavior
            )
        }

        let attributes = AlarmAttributes<ReminderAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: ReminderAlarmMetadata(reminderID: reminder.id),
            tintColor: .brand
        )

        return AlarmManager.AlarmConfiguration<ReminderAlarmMetadata>.alarm(
            schedule: .fixed(reminder.alertDate),
            attributes: attributes,
            stopIntent: intent(for: settings.stopAction, reminderID: reminder.id, alarmID: alarmID),
            secondaryIntent: secondaryButton == nil
                ? nil
                : intent(for: settings.secondaryAction, reminderID: reminder.id, alarmID: alarmID)
        )
    }

    nonisolated private static func button(for action: AlarmAction, settings: AppSettings) -> AlarmButton? {
        switch action {
        case .complete:
            return AlarmButton(text: "Completar", textColor: .white, systemImageName: "checkmark.circle.fill")
        case .snooze:
            return AlarmButton(
                text: LocalizedStringResource(stringLiteral: "Posponer \(settings.defaultSnooze.shortLabel)"),
                textColor: .white,
                systemImageName: "zzz"
            )
        case .snoozeOptions:
            return AlarmButton(text: "Posponer…", textColor: .white, systemImageName: "clock.arrow.circlepath")
        case .none:
            return nil
        }
    }

    nonisolated private static func intent(for action: AlarmAction, reminderID: UUID, alarmID: UUID) -> (any LiveActivityIntent)? {
        switch action {
        case .complete: return CompleteReminderIntent(reminderID: reminderID, alarmID: alarmID)
        case .snooze: return SnoozeReminderIntent(reminderID: reminderID, alarmID: alarmID)
        case .snoozeOptions: return SnoozeOptionsIntent(reminderID: reminderID, alarmID: alarmID)
        case .none: return nil
        }
    }
}

extension Color {
    /// Color de la app (también tiñe las alarmas, que no pueden usar el AccentColor del catálogo).
    static let brand = Color(red: 0.95, green: 0.38, blue: 0.20)
}
