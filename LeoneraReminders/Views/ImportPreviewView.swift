import SwiftUI

struct ImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let result: ReminderCSVImporter.Result
}

/// Muestra lo que se va a importar del CSV y deja elegir cómo tratar duplicados y vencidos.
struct ImportPreviewView: View {
    let preview: ImportPreview

    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var skipDuplicates = true
    @State private var advancePastDue = true

    var body: some View {
        let prepared = ReminderCSVImporter.prepare(
            preview.result.reminders,
            existing: store.reminders,
            skipDuplicates: skipDuplicates,
            advancePastDueRepeating: advancePastDue
        )
        NavigationStack {
            List {
                Section {
                    LabeledContent("Archivo", value: preview.fileName)
                    LabeledContent("Filas leídas", value: "\(preview.result.entries.count)")
                    LabeledContent("Con repetición", value: "\(prepared.reminders.filter { $0.repeatRule != nil }.count)")
                    if prepared.duplicates > 0 {
                        LabeledContent("Duplicados omitidos", value: "\(prepared.duplicates)")
                    }
                }
                Section {
                    Toggle("Omitir duplicados", isOn: $skipDuplicates)
                    Toggle("Pasar repetitivos vencidos a su próxima fecha", isOn: $advancePastDue)
                } footer: {
                    Text("Un duplicado tiene el mismo título que uno que ya tienes y la misma fecha o la misma repetición. Los vencidos que queden se programan para sonar en el siguiente minuto.")
                }

                if !preview.result.issues.isEmpty {
                    Section("Avisos") {
                        ForEach(preview.result.issues) { issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.title.isEmpty ? "Línea \(issue.line)" : issue.title)
                                Text("Línea \(issue.line): \(issue.message)")
                                    .font(.caption)
                                    .foregroundStyle(issue.kind == .skipped ? Color.red : Color.orange)
                            }
                        }
                    }
                }

                Section("Se importarán \(prepared.reminders.count)") {
                    ForEach(prepared.reminders) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                            Text(DateText.relative(reminder.dueDate))
                                .font(.subheadline)
                                .foregroundStyle(reminder.isOverdue() ? Color.red : Color.secondary)
                            if let rule = reminder.repeatRule {
                                Label(rule.summary(), systemImage: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importar CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") {
                        store.importReminders(prepared.reminders)
                        dismiss()
                    }
                    .disabled(prepared.reminders.isEmpty)
                }
            }
        }
    }
}
