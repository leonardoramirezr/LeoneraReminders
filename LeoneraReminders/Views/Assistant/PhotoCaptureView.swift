import PhotosUI
import SwiftUI
import UIKit

/// Una foto elegida, ya reducida a JPEG para mandarla.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let preview: UIImage
}

/// Crear recordatorios con fotos (de la cámara o de Fotos) y, si se quiere, indicaciones escritas o dictadas.
/// Al final se revisan los recordatorios como con la voz.
struct PhotoCaptureView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(GroqKeyStore.self) private var keyStore
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [CapturedPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isLoadingPhotos = false
    @State private var instructions = ""
    @State private var dictation = DictationSession()
    @State private var isProcessing = false
    @State private var processError: String?
    @State private var processTask: Task<Void, Never>?
    @State private var review: ReminderReview?

    private var remaining: Int { ReminderAssistant.maxImages - photos.count }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            Group {
                if keyStore.hasKey {
                    form
                } else {
                    AssistantSetupPrompt()
                }
            }
            .navigationTitle("Nuevo con una foto")
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
        .interactiveDismissDisabled(!photos.isEmpty || !instructions.isEmpty || dictation.phase != .idle || isProcessing)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { add(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in load(items) }
        .onDisappear {
            // Abrir la cámara (pantalla completa) también lo dispara; ahí no hay que detener nada.
            guard !showCamera else { return }
            dictation.cancel()
            processTask?.cancel()
        }
    }

    private var form: some View {
        Form {
            Section {
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { photo in
                                thumbnail(photo)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if remaining > 0 {
                    Group {
                        if cameraAvailable {
                            Button {
                                showCamera = true
                            } label: {
                                Label(photos.isEmpty ? "Tomar foto" : "Tomar otra foto", systemImage: "camera")
                            }
                        }
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: remaining, matching: .images) {
                            Label("Elegir de Fotos", systemImage: "photo.on.rectangle")
                        }
                    }
                    .disabled(isProcessing || isLoadingPhotos || dictation.phase != .idle)
                }
                if isLoadingPhotos {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Cargando fotos…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Fotos")
            } footer: {
                Text("Hasta \(ReminderAssistant.maxImages) fotos: notas, listas, citas, recibos, invitaciones o capturas de pantalla.")
            }

            Section {
                TextField("Por ejemplo: «sólo lo del viernes» o «avísame un día antes»", text: $instructions, axis: .vertical)
                    .lineLimit(2...8)
                DictationRow(session: dictation, title: "Dictar indicaciones", onText: appendInstructions)
            } header: {
                Text("Indicaciones (opcional)")
            } footer: {
                Text("Escribe o dicta qué recordar. Sin indicaciones se crea un recordatorio por cada tarea, cita o fecha límite que aparezca.")
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
                .disabled(photos.isEmpty || isLoadingPhotos || dictation.phase != .idle)
        }
    }

    private func thumbnail(_ photo: CapturedPhoto) -> some View {
        Image(uiImage: photo.preview)
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 96)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation { photos.removeAll { $0.id == photo.id } }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.borderless)
                .padding(4)
                .accessibilityLabel("Quitar foto")
            }
    }

    // MARK: - Acciones

    private func add(_ image: UIImage) {
        guard remaining > 0,
              let jpeg = ReminderAssistant.jpegForUpload(image),
              let preview = UIImage(data: jpeg)
        else { return }
        withAnimation { photos.append(CapturedPhoto(jpeg: jpeg, preview: preview)) }
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    add(image)
                }
            }
            pickerItems = []
            isLoadingPhotos = false
        }
    }

    private func appendInstructions(_ text: String) {
        let current = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        instructions = current.isEmpty ? text : current + " " + text
    }

    private func process() {
        let text = instructions
        let images = photos.map(\.jpeg)
        processError = nil
        isProcessing = true
        processTask = Task {
            defer { isProcessing = false }
            do {
                let drafts = try await ReminderAssistant.reminders(from: text, images: images)
                guard !Task.isCancelled else { return }
                review = ReminderReview(drafts: drafts, sourceText: text, photoCount: images.count)
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

/// La cámara del sistema para tomar una foto; `onFinish` recibe `nil` si se canceló.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil)
        }
    }
}
