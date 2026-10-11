import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ReminderListView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AlarmSyncService.self) private var alarms
    @Environment(\.openURL) private var openURL

    @State private var editing: EditorTarget?
    @State private var acting: ReminderSheetID?
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var importPreview: ImportPreview?
    @State private var importError: String?
    @State private var showCompleted = false
    @State private var searchText = ""
    @State private var completedTrigger = 0

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
            .navigationTitle("Recordatorios")
            .searchable(text: $searchText, prompt: "Buscar")
            .toolbar { toolbar }
            .overlay {
                if store.reminders.isEmpty {
                    ContentUnavailableView {
                        Label("Sin recordatorios", systemImage: "alarm")
                    } description: {
                        Text("Crea uno con + o importa un CSV exportado de Due.")
                    } actions: {
                        Button("Importar CSV…") { showImporter = true }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: completedTrigger)
        .sheet(item: $editing) { target in
            ReminderEditorView(target: target, existing: target.reminderID.flatMap(store.reminder(id:)))
        }
        .sheet(item: $acting) { sheet in
            ReminderActionSheet(reminderID: sheet.id) {
                acting = nil
                editing = .edit(sheet.id)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $importPreview) { preview in
            ImportPreviewView(preview: preview)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
        ) { result in
            handleImport(result)
        }
        .alert("No se pudo importar", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onChange(of: store.pendingOptionsReminderID, initial: true) { _, id in
            // La alarma pidió completar o posponer.
            guard let id else { return }
            store.pendingOptionsReminderID = nil
            editing = nil
            acting = ReminderSheetID(id: id)
        }
    }

    // MARK: - Lista

    private func list(now: Date) -> some View {
        let grouped = sections(now: now)
        let completed = filtered.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return List {
            statusSection

            ForEach(grouped) { section in
                Section {
                    ForEach(section.reminders) { reminder in
                        row(reminder, now: now)
                    }
                } header: {
                    Text(section.title)
                        .foregroundStyle(section.isOverdue ? Color.red : Color.secondary)
                }
            }

            if !completed.isEmpty {
                Section {
                    Button {
                        withAnimation { showCompleted.toggle() }
                    } label: {
                        Label(
                            showCompleted ? "Ocultar completados" : "Mostrar completados (\(completed.count))",
                            systemImage: showCompleted ? "chevron.up" : "chevron.down"
                        )
                    }
                    if showCompleted {
                        ForEach(completed) { reminder in
                            row(reminder, now: now)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ reminder: Reminder, now: Date) -> some View {
        ReminderRow(
            reminder: reminder,
            now: now,
            isRinging: reminder.scheduledAlarms.contains { alarms.alertingAlarmIDs.contains($0.id) },
            onToggle: {
                // Completar siempre pide deslizar; reabrir un completado es inofensivo.
                if reminder.isCompleted {
                    store.markIncomplete(id: reminder.id)
                } else {
                    acting = ReminderSheetID(id: reminder.id)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { editing = .edit(reminder.id) }
        .swipeActions(edge: .leading) {
            if !reminder.isCompleted {
                Button { complete(reminder) } label: {
                    Label("Completar", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.delete(ids: [reminder.id]) } label: {
                Label("Eliminar", systemImage: "trash")
            }
            if !reminder.isCompleted {
                Button { acting = ReminderSheetID(id: reminder.id) } label: {
                    Label("Posponer", systemImage: "zzz")
                }
                .tint(.indigo)
            }
        }
        .contextMenu { menuItems(for: reminder) }
    }

    @ViewBuilder
    private func menuItems(for reminder: Reminder) -> some View {
        if reminder.isCompleted {
            Button { store.markIncomplete(id: reminder.id) } label: {
                Label("Marcar como pendiente", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button { acting = ReminderSheetID(id: reminder.id) } label: {
                Label("Completar…", systemImage: "checkmark")
            }
            Menu {
                ForEach(settingsStore.settings.sortedSnoozeOptions) { option in
                    Button("Recordar en \(option.longLabel)") { store.snooze(id: reminder.id, by: option) }
                }
            } label: {
                Label("Posponer", systemImage: "zzz")
            }
            if reminder.snoozedUntil != nil {
                Button { store.clearSnooze(id: reminder.id) } label: {
                    Label("Quitar posposición", systemImage: "xmark.circle")
                }
            }
        }
        Button { editing = .edit(reminder.id) } label: {
            Label("Editar", systemImage: "pencil")
        }
        Button(role: .destructive) { store.delete(ids: [reminder.id]) } label: {
            Label("Eliminar", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch alarms.authorizationState {
        case .denied:
            Section {
                Label("Las alarmas están desactivadas", systemImage: "alarm.waves.left.and.right")
                    .foregroundStyle(.red)
                Text("Sin este permiso los recordatorios no sonarán. Actívalo en Configuración.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Abrir Configuración") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        case .notDetermined:
            Section {
                Button {
                    Task { await alarms.requestAuthorization() }
                } label: {
                    Label("Permitir alarmas", systemImage: "alarm")
                }
            } footer: {
                Text("Leonera usa alarmas para que cada recordatorio suene a su hora, aun en silencio.")
            }
        default:
            if alarms.limitReached {
                Section {
                    Label("Se alcanzó el máximo de alarmas del sistema; los recordatorios más lejanos se programarán cuando se liberen.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
            }
        }
        if let error = store.lastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { showImporter = true } label: {
                    Label("Importar CSV…", systemImage: "square.and.arrow.down")
                }
                Button { showSettings = true } label: {
                    Label("Configuración", systemImage: "gear")
                }
                if store.reminders.contains(where: \.isCompleted) {
                    Button(role: .destructive) { store.deleteCompleted() } label: {
                        Label("Eliminar completados", systemImage: "trash")
                    }
                }
            } label: {
                Label("Más", systemImage: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { editing = .new } label: {
                Label("Nuevo recordatorio", systemImage: "plus")
            }
        }
    }

    // MARK: - Datos

    private var filtered: [Reminder] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.reminders }
        return store.reminders.filter { $0.title.localizedStandardContains(query) }
    }

    private struct ReminderSection: Identifiable {
        let id: String
        let title: String
        let reminders: [Reminder]
        var isOverdue = false
    }

    private func sections(now: Date) -> [ReminderSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: today) ?? now
        let nextWeek = calendar.date(byAdding: .day, value: 8, to: today) ?? now

        var overdue: [Reminder] = [], todays: [Reminder] = [], tomorrows: [Reminder] = []
        var week: [Reminder] = [], later: [Reminder] = []
        for reminder in filtered.filter({ !$0.isCompleted }).sorted(by: { $0.alertDate < $1.alertDate }) {
            let date = reminder.alertDate
            if date <= now { overdue.append(reminder) }
            else if date < tomorrow { todays.append(reminder) }
            else if date < dayAfter { tomorrows.append(reminder) }
            else if date < nextWeek { week.append(reminder) }
            else { later.append(reminder) }
        }
        return [
            ReminderSection(id: "overdue", title: "Vencidos", reminders: overdue, isOverdue: true),
            ReminderSection(id: "today", title: "Hoy", reminders: todays),
            ReminderSection(id: "tomorrow", title: "Mañana", reminders: tomorrows),
            ReminderSection(id: "week", title: "Próximos 7 días", reminders: week),
            ReminderSection(id: "later", title: "Más adelante", reminders: later),
        ].filter { !$0.reminders.isEmpty }
    }

    /// Sólo desde el deslizamiento de la fila (que ya es un gesto deliberado).
    private func complete(_ reminder: Reminder) {
        withAnimation { store.complete(id: reminder.id) }
        completedTrigger += 1
    }

    private func handleImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = ReminderCSVImporter.decodeText(data) else {
                    importError = "No se pudo leer el archivo como texto."
                    return
                }
                let parsed = try ReminderCSVImporter.parse(text)
                importPreview = ImportPreview(fileName: url.lastPathComponent, result: parsed)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let now: Date
    let isRinging: Bool
    let onToggle: () -> Void

    private var isOverdue: Bool { reminder.isOverdue(now: now) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(reminder.isCompleted ? Color.green : (isOverdue ? Color.red : Color.secondary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(reminder.isCompleted ? "Marcar como pendiente" : "Completar")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? Color.secondary : Color.primary)

                if let completedAt = reminder.completedAt {
                    Label("Completado \(DateText.relative(completedAt, now: now))", systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label(DateText.relative(reminder.dueDate, now: now), systemImage: alarmSymbol)
                        .font(.subheadline)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                    if isOverdue, let next = reminder.scheduledAlarms.first(where: { $0.fireDate > now }) {
                        Label("Vuelve a sonar \(DateText.time(next.fireDate))", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(Color.brand)
                    }
                    if let snoozed = reminder.snoozedUntil {
                        Label("Pospuesto hasta \(DateText.relative(snoozed, now: now))", systemImage: "zzz")
                            .font(.subheadline)
                            .foregroundStyle(.indigo)
                    }
                }
                if let rule = reminder.repeatRule {
                    Label(rule.summary(), systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isRinging {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .foregroundStyle(Color.brand)
                    .symbolEffect(.wiggle, options: .repeating)
                    .accessibilityLabel("Sonando")
            }
        }
        .padding(.vertical, 2)
    }

    private var alarmSymbol: String {
        if reminder.isCompleted { return "checkmark" }
        return reminder.scheduledAlarms.isEmpty ? "bell.slash" : "alarm"
    }
}
