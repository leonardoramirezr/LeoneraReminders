import Foundation
import UserNotifications

/// Entrega de recordatorios con notificaciones locales, para cuando se quiere respetar el modo silencio
/// (las alarmas de AlarmKit siempre suenan). Los botones hacen lo mismo que los de la alarma.
@MainActor
final class NotificationDelivery: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelivery()
    /// iOS sólo conserva 64 notificaciones pendientes por app.
    static let maxPending = 64

    nonisolated private static let categoryID = "reminder"
    nonisolated private static let snoozeActionID = "snooze"
    nonisolated private static let optionsActionID = "options"
    nonisolated private static let reminderKey = "reminderID"
    nonisolated private static let alarmKey = "alarmID"

    private let center = UNUserNotificationCenter.current()

    /// Debe llamarse al arrancar para recibir las respuestas a las notificaciones.
    func configure() {
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Reemplaza todas las notificaciones pendientes por `items`.
    func replaceAll(_ items: [(reminder: Reminder, record: ScheduledAlarm)], settings: AppSettings) async {
        registerCategory(settings: settings)
        center.removeAllPendingNotificationRequests()
        let calendar = Calendar.current
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.reminder.title
            content.body = item.record.fireDate == item.reminder.alertDate ? "Recordatorio" : "Sigue pendiente"
            content.sound = Self.sound(for: settings.sound)
            content.categoryIdentifier = Self.categoryID
            content.interruptionLevel = .active
            content.userInfo = [
                Self.reminderKey: item.reminder.id.uuidString,
                Self.alarmKey: item.record.id.uuidString,
            ]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.record.fireDate)
            let request = UNNotificationRequest(
                identifier: item.record.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func removeAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Quita del Centro de notificaciones las de recordatorios que ya no están pendientes.
    func removeDelivered(keeping pending: Set<UUID>) async {
        let stale = await center.deliveredNotifications().compactMap { notification -> String? in
            let id = (notification.request.content.userInfo[Self.reminderKey] as? String).flatMap(UUID.init(uuidString:))
            return id.map(pending.contains) == true ? nil : notification.request.identifier
        }
        if !stale.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    private func registerCategory(settings: AppSettings) {
        var actions: [UNNotificationAction] = []
        switch settings.secondaryAction {
        case .snooze:
            actions.append(UNNotificationAction(identifier: Self.snoozeActionID, title: "Posponer \(settings.defaultSnooze.shortLabel)"))
        case .snoozeOptions:
            actions.append(UNNotificationAction(identifier: Self.optionsActionID, title: "Completar…", options: [.foreground]))
        case .none:
            break
        }
        if settings.secondaryAction != .snooze {
            actions.append(UNNotificationAction(identifier: Self.snoozeActionID, title: "Posponer \(settings.defaultSnooze.shortLabel)"))
        }
        let category = UNNotificationCategory(
            identifier: Self.categoryID, actions: actions, intentIdentifiers: [], options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    private static func sound(for sound: AlarmSound) -> UNNotificationSound? {
        switch sound {
        case .system: .default
        case .silent: nil
        default: sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let reminderID = info[Self.reminderKey] as? String ?? ""
        let alarmID = info[Self.alarmKey] as? String ?? ""
        switch response.actionIdentifier {
        case Self.snoozeActionID:
            await AlarmActionHandler.perform(.snooze, reminderID: reminderID, alarmID: alarmID)
        case Self.optionsActionID, UNNotificationDefaultActionIdentifier:
            await AlarmActionHandler.perform(.snoozeOptions, reminderID: reminderID, alarmID: alarmID)
        case UNNotificationDismissActionIdentifier:
            await AlarmActionHandler.performStopAction(reminderID: reminderID, alarmID: alarmID)
        default:
            break
        }
    }
}
