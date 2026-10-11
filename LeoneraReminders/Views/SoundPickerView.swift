import AVFoundation
import SwiftUI

/// Lista de sonidos: al tocar uno se elige y se escucha.
struct SoundPickerView: View {
    @Binding var selection: AlarmSound
    @State private var player = SoundPreviewPlayer()

    var body: some View {
        List {
            Section {
                ForEach(AlarmSound.allCases) { sound in
                    Button {
                        selection = sound
                        player.play(sound)
                    } label: {
                        HStack {
                            Label(sound.label, systemImage: sound == .silent ? "speaker.slash" : "speaker.wave.2")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if sound == selection {
                                Image(systemName: "checkmark").foregroundStyle(Color.brand)
                            }
                        }
                    }
                }
            } footer: {
                Text("Toca un sonido para escucharlo. Con «Sin sonido» la alarma aparece igual en pantalla, pero en silencio.")
            }
        }
        .navigationTitle("Sonido")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }
}

/// Reproduce unos segundos del sonido elegido.
@MainActor
final class SoundPreviewPlayer {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ sound: AlarmSound) {
        stop()
        if sound == .system {
            AudioServicesPlaySystemSound(1005)
            return
        }
        guard let name = sound.fileName, sound != .silent,
              let url = Bundle.main.url(forResource: name, withExtension: nil)
        else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        player?.stop()
        player = nil
    }
}
