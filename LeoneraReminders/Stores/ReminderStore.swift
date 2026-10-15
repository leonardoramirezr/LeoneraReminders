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
    /// El último cambio que se puede deshacer (completar, modificar, posponer o eliminar).
    private(set) var undoable: UndoableChange?

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

    /// Agrega varios a la vez (los que se crearon con voz o fotos); «Deshacer» los quita juntos.
    /// Los que ya vencieron suenan en el siguiente minuto.
    func add(contentsOf added: [Reminder]) {
        guard !added.isEmpty else { return }
        undoable = UndoableChange(
            message: added.count == 1 ? "Recordatorio agregado" : "\(added.count) recordatorios agregados",
            previous: [],
            added: Set(added.map(\.id))
        )
        reminders.append(contentsOf: added)
        retryOverdue()
        didChange()
    }

    /// Reemplaza el recordatorio con el mismo id (conserva la alarma registrada, que sólo cambia la sincronización).
    func update(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let previous = reminders[index]
        var updated = reminder
        updated.scheduledAlarms = previous.scheduledAlarms
        guard updated != previous else { return }
        let message = updated.lastCompletedAt != previous.lastCompletedAt
            ? completedMessage(updated)
            : "Recordatorio modificado"
        registerUndo(message, ids: [reminder.id])
        reminders[index] = updated
        didChange()
    }

    func delete(ids: some Collection<UUID>) {
        let set = Set(ids)
        let count = reminders.count(where: { set.contains($0.id) })
        guard count > 0 else { return }
        registerUndo(count == 1 ? "Recordatorio eliminado" : "\(count) recordatorios eliminados", ids: set)
        reminders.removeAll { set.contains($0.id) }
        didChange()
    }

    func deleteCompleted() {
        delete(ids: reminders.filter(\.isCompleted).map(\.id))
    }

    func complete(id: UUID) {
        guard let reminder = reminder(id: id) else { return }
        var completed = reminder
        completed.complete()
        registerUndo(completedMessage(completed), ids: [id])
        mutate(id) { $0 = completed }
    }

    func markIncomplete(id: UUID) {
        registerUndo("Marcado como pendiente", ids: [id])
        mutate(id) { $0.markIncomplete() }
    }

    /// `undoable` en falso cuando lo pide la alarma (no hay nadie viendo la app para deshacerlo).
    func snooze(id: UUID, by amount: TimeAmount, undoable: Bool = true) {
        if undoable { registerUndo("Se recordará en \(amount.longLabel)", ids: [id]) }
        mutate(id) { $0.snooze(by: amount) }
    }

    func reschedule(id: UUID, to date: Date) {
        registerUndo("Recordatorio modificado", ids: [id])
        mutate(id) { $0.reschedule(to: date) }
    }

    // MARK: - Deshacer

    /// Copia de los recordatorios tal como estaban antes de un cambio, con su posición en la lista,
    /// y los que el cambio agregó.
    struct UndoableChange: Identifiable {
        let id = UUID()
        let message: String
        fileprivate let previous: [(index: Int, reminder: Reminder)]
        fileprivate var added: Set<UUID> = []
    }

    /// Devuelve los recordatorios afectados a como estaban. Los cambios hechos a otros recordatorios después se respetan.
    func undo() {
        guard let change = undoable else { return }
        undoable = nil
        // Se cancelan sus alarmas en la siguiente sincronización.
        reminders.removeAll { change.added.contains($0.id) }
        for (index, old) in change.previous {
            var restored = old
            if let current = reminders.firstIndex(where: { $0.id == old.id }) {
                restored.scheduledAlarms = reminders[current].scheduledAlarms
                reminders[current] = restored
            } else {
                // Se había eliminado: sus alarmas ya se cancelaron, la sincronización programa las nuevas.
                restored.scheduledAlarms = []
                reminders.insert(restored, at: min(index, reminders.count))
            }
        }
        didChange()
    }

    /// Se llama cuando el aviso de deshacer deja de mostrarse.
    func discardUndo(id: UndoableChange.ID) {
        if undoable?.id == id { undoable = nil }
    }

    private func registerUndo(_ message: String, ids: Set<UUID>) {
        let previous = reminders.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { (index: $0.offset, reminder: $0.element) }
        guard !previous.isEmpty else { return }
        undoable = UndoableChange(message: message, previous: previous)
    }

    private func completedMessage(_ reminder: Reminder) -> String {
        reminder.isCompleted ? "Recordatorio completado" : "Completado · siguiente \(DateText.relative(reminder.dueDate))"
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

    /// Registra las alarmas programadas de todos los recordatorios (los que no aparecen quedan sin alarmas).
    /// No dispara otra sincronización.
    ///
    /// Se aplica de una vez (un solo cambio observado y un solo guardado) para no redibujar la lista
    /// una vez por recordatorio mientras corre una animación.
    func setScheduledAlarms(_ alarmsByReminder: [UUID: [ScheduledAlarm]]) {
        var updated = reminders
        var changed = false
        for index in updated.indices {
            let alarms = alarmsByReminder[updated[index].id] ?? []
            if updated[index].scheduledAlarms != alarms {
                updated[index].scheduledAlarms = alarms
                changed = true
            }
        }
        guard changed else { return }
        reminders = updated
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

    /// Escribe en serie y fuera del hilo principal, para que guardar no trabe los gestos ni las animaciones.
    private static let saveQueue = DispatchQueue(label: "LeoneraReminders.store.save", qos: .utility)

    private func save() {
        let snapshot = reminders
        let fileURL = fileURL
        let logger = logger
        Self.saveQueue.async { [weak self] in
            let failed: Bool
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                failed = false
            } catch {
                failed = true
                logger.error("Error al guardar recordatorios: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in self?.setSaveFailed(failed) }
        }
    }

    private func setSaveFailed(_ failed: Bool) {
        let message = failed ? "No se pudieron guardar los recordatorios." : nil
        // Sólo se asigna si cambia: cada asignación hace que la lista se vuelva a dibujar.
        if lastError != message { lastError = message }
    }
}
