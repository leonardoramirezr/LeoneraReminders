import SwiftUI

struct ReminderEditorView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    @State private var draft: Reminder
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    init(target: EditorTarget, existing: Reminder?) {
        self.target = target
        _draft = State(initialValue: existing ?? Reminder(title: "", dueDate: Self.defaultDueDate()))
    }

    private var isNew: Bool { target.reminderID == nil }
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Cambiar la fecha límite reprograma la ocurrencia (quita la posposición).
    private var dueDate: Binding<Date> {
        Binding(get: { draft.dueDate }, set: { draft.reschedule(to: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $draft.title, axis: .vertical)
                        .focused($titleFocused)
                }

                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateText.relative(draft.dueDate))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(draft.dueDate < Date() ? Color.red : Color.primary)
                        Text(DateText.full(draft.dueDate))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Fecha y hora", selection: dueDate)
                    QuickAdjustGridView(grid: settingsStore.settings.quickAdjustGrid) { _, _, cell in
                        withAnimation(.snappy) { dueDate.wrappedValue = cell.apply(to: draft.dueDate) }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Fecha límite")
                }

                if let snoozed = draft.snoozedUntil {
                    Section {
                        LabeledContent("Pospuesto hasta", value: DateText.relative(snoozed))
                        Button("Quitar posposición") { draft.snoozedUntil = nil }
                    }
                }

                Section {
                    NavigationLink {
                        RepeatRuleEditorView(rule: $draft.repeatRule, dueDate: draft.dueDate)
                    } label: {
                        LabeledContent {
                            Text(draft.repeatRule?.summary() ?? "Nunca")
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label("Repetir", systemImage: "repeat")
                        }
                    }
                }

                if !isNew {
                    Section {
                        if draft.isCompleted {
                            Button("Marcar como pendiente") { draft.markIncomplete() }
                        } else {
                            Button(draft.repeatRule == nil ? "Marcar como completado" : "Completar esta vez") {
                                draft.complete()
                                save()
                            }
                        }
                        Button("Eliminar recordatorio", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Nuevo recordatorio" : "Editar recordatorio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .confirmationDialog("¿Eliminar este recordatorio?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    store.delete(ids: [draft.id])
                    dismiss()
                }
            }
            .onAppear {
                if isNew { titleFocused = true }
            }
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        var reminder = draft
        reminder.title = trimmedTitle
        if isNew {
            store.add(reminder)
        } else {
            store.update(reminder)
        }
        dismiss()
    }

    /// La siguiente hora en punto.
    static func defaultDueDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now.addingTimeInterval(3_600)
    }
}
