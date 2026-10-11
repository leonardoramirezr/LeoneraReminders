import SwiftUI

/// "Desliza para completar": hay que arrastrar el círculo hasta el final para confirmar,
/// así un toque accidental no completa nada.
struct SlideToConfirm: View {
    let title: String
    var tint: Color = .green
    let onConfirm: () -> Void

    @State private var offset: CGFloat = 0
    @State private var confirmed = false

    private let knob: CGFloat = 52
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let maxOffset = max(geometry.size.width - knob - inset * 2, 1)
            let progress = Double(offset / maxOffset)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.15))
                Capsule()
                    .fill(tint.opacity(0.35))
                    .frame(width: offset + knob + inset * 2)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knob)
                    .opacity(1 - progress)
                Circle()
                    .fill(tint)
                    .frame(width: knob, height: knob)
                    .overlay {
                        Image(systemName: confirmed ? "checkmark" : "chevron.right.2")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(inset)
                    .offset(x: offset)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                guard !confirmed else { return }
                                offset = min(max(0, value.translation.width), maxOffset)
                            }
                            .onEnded { _ in
                                guard !confirmed else { return }
                                if offset >= maxOffset * 0.9 {
                                    withAnimation(.snappy) { offset = maxOffset }
                                    confirm()
                                } else {
                                    withAnimation(.spring) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: knob + inset * 2)
        .sensoryFeedback(.success, trigger: confirmed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Desliza a la derecha hasta el final para confirmar")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { confirm() }
    }

    private func confirm() {
        guard !confirmed else { return }
        confirmed = true
        onConfirm()
    }
}
