import SwiftUI

/// Crear recordatorios con la voz: primero sólo se graba; ya convertido en texto se puede corregir (o dictar más)
/// antes de mandarlo al modelo, y al final se revisan los recordatorios que propuso.
struct VoiceCaptureView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(GroqKeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss

    @State private var dictation = DictationSession()
    @State private var transcript = ""
    /// Ya hubo una transcripción: se muestra el texto para corregirlo.
    @State private var showsTranscript = false
    @State private var isProcessing = false
    @State private var processError: String?
    @State private var processTask: Task<Void, Never>?
    @State private var review: ReminderReview?

    private var trimmedTranscript: String { transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if !keyStore.hasKey {
                    AssistantSetupPrompt()
                } else if showsTranscript {
                    transcriptStage
                } else {
                    recordingStage
                }
            }
            .navigationTitle("Nuevo con la voz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { close() }
                }
            }
            .navigationDestination(item: $review) { review in
                ReminderReviewView(review: review) { reminders in
                    store.add(contentsOf: reminders)
                    close()
                }
            }
        }
        .interactiveDismissDisabled(showsTranscript)
        .task {
            // Tocar «Voz» ya es la intención de hablar: empieza a grabar sin otro toque.
            if keyStore.hasKey { await dictation.start() }
        }
        .onDisappear {
            dictation.cancel()
            processTask?.cancel()
        }
    }

    // MARK: - Grabar

    private var recordingStage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(statusTitle)
                .font(.title3.weight(.semibold))
            Text("Di uno o varios recordatorios, por ejemplo: «mañana a las 9 llamar al dentista y todos los lunes sacar la basura».")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            RecordButton(phase: dictation.phase, level: dictation.recorder.level, action: toggleRecording)
            if dictation.phase == .recording {
                ElapsedText(since: dictation.recorder.startedAt)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let error = dictation.error {
                VStack(spacing: 10) {
                    DictationErrorView(session: dictation, error: error, onText: append)
                }
                .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .onChange(of: dictation.recorder.reachedLimit) { _, reached in
            if reached { toggleRecording() }
        }
    }

    private var statusTitle: String {
        switch dictation.phase {
        case .idle: "Toca para hablar"
        case .recording: "Escuchando…"
        case .transcribing: "Convirtiendo a texto…"
        }
    }

    private func toggleRecording() {
        switch dictation.phase {
        case .idle:
            Task { await dictation.start() }
        case .recording:
            Task { if let text = await dictation.finish() { append(text) } }
        case .transcribing:
            break
        }
    }

    private func append(_ text: String) {
        transcript = trimmedTranscript.isEmpty ? text : trimmedTranscript + " " + text
        showsTranscript = true
    }

    // MARK: - Corregir y procesar

    private var transcriptStage: some View {
        Form {
            Section {
                TextField("Lo que dijiste", text: $transcript, axis: .vertical)
                    .lineLimit(4...12)
            } header: {
                Text("Lo que dijiste")
            } footer: {
                Text("Corrige el texto si hace falta antes de crear los recordatorios.")
            }

            Section {
                DictationRow(session: dictation, title: "Dictar más", onText: append)
            }

            if let processError {
                Section {
                    Label(processError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ProcessButton(isProcessing: isProcessing, action: process)
                .disabled(trimmedTranscript.isEmpty || dictation.phase != .idle)
        }
    }

    private func process() {
        let text = trimmedTranscript
        processError = nil
        isProcessing = true
        processTask = Task {
            defer { isProcessing = false }
            do {
                let drafts = try await ReminderAssistant.reminders(from: text)
                guard !Task.isCancelled else { return }
                review = ReminderReview(drafts: drafts, sourceText: text)
            } catch {
                guard !Task.isCancelled else { return }
                processError = error.localizedDescription
            }
        }
    }

    private func close() {
        dictation.cancel()
        processTask?.cancel()
        dismiss()
    }
}

/// «Crear recordatorios», abajo de la pantalla; mientras el modelo responde muestra un indicador.
struct ProcessButton: View {
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                    Text("Creando recordatorios…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Crear recordatorios")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brand)
        .disabled(isProcessing)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
