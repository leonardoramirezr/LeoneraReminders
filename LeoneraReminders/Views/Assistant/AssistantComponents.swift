import SwiftUI
import UIKit

/// Cómo se crea un recordatorio con el asistente.
enum AssistantSource: String, Identifiable {
    case voice
    case photo

    var id: String { rawValue }
}

/// Barra flotante de abajo, al estilo de la de Instagram: una cápsula de vidrio con sólo íconos. De izquierda a
/// derecha: buscar, y las tres formas de crear un recordatorio (con una foto, con la voz o a mano).
struct AddReminderBar: View {
    let onSearch: () -> Void
    let onPhoto: () -> Void
    let onVoice: () -> Void
    let onManual: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button(systemImage: "magnifyingglass", accessibility: "Buscar", action: onSearch)
                .keyboardShortcut("f", modifiers: .command)
            button(systemImage: "camera", accessibility: "Nuevo recordatorio con una foto", action: onPhoto)
            button(systemImage: "mic", accessibility: "Nuevo recordatorio con la voz", action: onVoice)
            button(systemImage: "square.and.pencil", accessibility: "Nuevo recordatorio a mano", action: onManual)
                .keyboardShortcut("n", modifiers: .command)
        }
        .padding(5)
        .frame(height: 62)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 22)
        .padding(.bottom, 4)
    }

    private func button(systemImage: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.capsule)
        }
        .buttonStyle(BarButtonStyle())
        .accessibilityLabel(accessibility)
    }
}

/// Ícono sin borde que, al tocarlo, se marca con la cápsula gris de la pestaña activa de Instagram.
private struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0))
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Se muestra en lugar de la captura de voz o fotos mientras no haya clave de Groq.
struct AssistantSetupPrompt: View {
    var body: some View {
        ContentUnavailableView {
            Label("Configura Groq", systemImage: "key")
        } description: {
            Text("Para crear recordatorios con la voz o con fotos, agrega tu clave de API de Groq.")
        } actions: {
            NavigationLink("Agregar clave") {
                AssistantSettingsView()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Botón grande para grabar: micrófono, detener (con el nivel de la voz alrededor) o un indicador mientras se
/// convierte en texto.
struct RecordButton: View {
    let phase: DictationSession.Phase
    let level: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill((phase == .recording ? Color.red : Color.brand).opacity(0.18))
                    .scaleEffect(phase == .recording ? 1 + level * 0.45 : 0.8)
                Circle()
                    .fill(phase == .recording ? Color.red : Color.brand)
                    .frame(width: 96, height: 96)
                if phase == .transcribing {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 150, height: 150)
            .animation(.easeOut(duration: 0.12), value: level)
            .animation(.snappy, value: phase)
        }
        .buttonStyle(.plain)
        .disabled(phase == .transcribing)
        .accessibilityLabel(phase == .recording ? "Terminar de grabar" : "Empezar a grabar")
    }
}

/// Fila para dictar dentro de un formulario: graba, convierte la voz en texto con Groq y lo entrega a `onText`.
struct DictationRow: View {
    let session: DictationSession
    let title: String
    let onText: (String) -> Void

    var body: some View {
        switch session.phase {
        case .idle:
            Button {
                Task { await session.start() }
            } label: {
                Label(title, systemImage: "mic")
            }
            if let error = session.error {
                DictationErrorView(session: session, error: error, onText: onText)
            }
        case .recording:
            HStack(spacing: 12) {
                LevelIndicator(level: session.recorder.level)
                ElapsedText(since: session.recorder.startedAt)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    session.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Descartar grabación")
                Button {
                    finish()
                } label: {
                    Label("Listo", systemImage: "stop.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(.red)
            }
            .onChange(of: session.recorder.reachedLimit) { _, reached in
                if reached { finish() }
            }
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Convirtiendo a texto…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finish() {
        Task {
            if let text = await session.finish() { onText(text) }
        }
    }
}

/// Error del dictado, con «Reintentar» si se conservó la grabación o el acceso a Configuración si falta el permiso.
struct DictationErrorView: View {
    let session: DictationSession
    let error: String
    let onText: (String) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
        if session.needsMicrophonePermission {
            Button("Abrir Configuración") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } else if session.canRetry {
            Button("Reintentar con la misma grabación") {
                Task {
                    if let text = await session.retry() { onText(text) }
                }
            }
        }
    }
}

/// Barras que suben y bajan con la voz.
struct LevelIndicator: View {
    let level: Double

    private let weights = [0.55, 0.8, 1.0, 0.8, 0.55]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 4, height: 6 + 18 * min(1, level * weights[index] * 1.3))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

/// "0:42" desde que empezó la grabación.
struct ElapsedText: View {
    let since: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since ?? context.date)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .monospacedDigit()
        }
    }
}
