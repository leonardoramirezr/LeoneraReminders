import SwiftUI

/// Completar o "Recordar en…" con todas las opciones configuradas.
/// Se abre desde la lista o desde el botón «Más opciones» de la alarma.
struct SnoozeOptionsSheet: View {
    let reminderID: UUID
    /// Abre el editor para elegir otra fecha.
    let onEdit: () -> Void

    @Environment(ReminderStore.self) private var store
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if let reminder = store.reminder(id: reminderID) {
                    content(for: reminder)
                } else {
                    ContentUnavailableView("El recordatorio ya no existe", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle("Posponer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func content(for reminder: Reminder) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(reminder.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(subtitle(for: reminder))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    store.complete(id: reminder.id)
                    dismiss()
                } label: {
                    Label(reminder.repeatRule == nil ? "Completar" : "Completar esta vez", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recordar en…")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(settingsStore.settings.sortedSnoozeOptions) { option in
                            Button {
                                store.snooze(id: reminder.id, by: option)
                                dismiss()
                            } label: {
                                Text(option.shortLabel)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(option == settingsStore.settings.defaultSnooze ? Color.brand : Color.secondary)
                        }
                    }
                }

                Button("Elegir otra fecha…", action: onEdit)
            }
            .padding()
        }
    }

    private func subtitle(for reminder: Reminder) -> String {
        if let snoozed = reminder.snoozedUntil {
            return "Pospuesto hasta \(DateText.relative(snoozed))"
        }
        return "Fecha límite: \(DateText.relative(reminder.dueDate))"
    }
}
