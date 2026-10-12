import Foundation
import Observation
import os

/// Guarda los recordatorios en un archivo JSON y avisa a `AlarmSyncService` cuando cambian.
@MainActor
@Observable
final class ReminderStore {
    static let shared = ReminderStore()

    private(set) var reminders: [Reminder] = []
    /// Recordatorio que se pospuso con "Más opciones" desde la alarma: la app muestra las opciones al abrirse.
    var pendingOptionsReminderID: UUID?
    private(set) var lastError: String?

    private let fileURL: URL
    private let logger = Logger(subsystem: "LeoneraReminders", category: "store")

    init(fileURL: URL = ReminderStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultFileURL: URL {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.documentsDirectory
        return directory.appending(path: "reminders.json")
    }

    // MARK: - Consultas

    func reminder(id: UUID) -> Reminder? {
        reminders.first { $0.id == id }
    }

    // MARK: - Cambios

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        didChange()
    }

    /// Reemplaza el recordatorio con el mismo id (conserva la alarma registrada, que sólo cambia la sincronización).
    func update(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        var updated = reminder
        updated.scheduledAlarms = reminders[index].scheduledAlarms
        reminders[index] = updated
        didChange()
    }

    func delete(ids: some Collection<UUID>) {
        let set = Set(ids)
        reminders.removeAll { set.contains($0.id) }
        didChange()
    }

    func deleteCompleted() {
        reminders.removeAll(where: \.isCompleted)
        didChange()
    }

    func complete(id: UUID) {
        mutate(id) { $0.complete() }
    }

    func markIncomplete(id: UUID) {
        mutate(id) { $0.markIncomplete() }
    }

    func snooze(id: UUID, by amount: TimeAmount) {
        mutate(id) { $0.snooze(by: amount) }
    }

    func reschedule(id: UUID, to date: Date) {
        mutate(id) { $0.reschedule(to: date) }
    }

    func importReminders(_ imported: [Reminder]) {
        guard !imported.isEmpty else { return }
        reminders.append(contentsOf: imported)
        retryOverdue()
        didChange()
    }

    /// Hace que todos los vencidos sin atender vuelvan a sonar en el siguiente minuto
    /// (salvo los que ya están sonando o van a sonar antes). Se llama al entrar a la app.
    func retryOverdue(ringing: Set<UUID> = []) {
        let followUp = SettingsStore.shared.settings.followUp
        var changed = false
        for index in reminders.indices
        where !reminders[index].scheduledAlarms.contains(where: { ringing.contains($0.id) }) {
            if reminders[index].retryIfOverdue(followUp: followUp) { changed = true }
        }
        if changed { didChange() }
    }

    /// Registra las alarmas programadas. No dispara otra sincronización.
    func setScheduledAlarms(_ alarms: [ScheduledAlarm], for id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }),
              reminders[index].scheduledAlarms != alarms
        else { return }
        reminders[index].scheduledAlarms = alarms
        save()
    }

    private func mutate(_ id: UUID, _ change: (inout Reminder) -> Void) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        change(&reminders[index])
        didChange()
    }

    private func didChange() {
        save()
        AlarmSyncService.shared.requestSync()
    }

    // MARK: - Archivo

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            reminders = try JSONDecoder().decode([Reminder].self, from: data)
        } catch {
            // No se sobrescribe el archivo dañado: se guarda una copia antes de seguir.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            lastError = "No se pudieron leer los recordatorios guardados (se respaldó el archivo)."
            logger.error("Error al leer recordatorios: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(reminders)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastError = nil
        } catch {
            lastError = "No se pudieron guardar los recordatorios."
            logger.error("Error al guardar recordatorios: \(error.localizedDescription, privacy: .public)")
        }
    }
}
