import SwiftUI

/// Timeline with buffered range, opening marker and a draggable thumb.
struct PlayerScrubber: View {
    let current: Double
    let buffered: Double
    let duration: Double
    var opening: TimeRange?
    let isScrubbing: Bool
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    private func fraction(_ value: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, value / duration)))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height: CGFloat = isScrubbing ? 8 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white.opacity(0.38)).frame(width: width * fraction(buffered))
                if let opening, duration > 0 {
                    Capsule()
                        .fill(Theme.violet.opacity(0.7))
                        .frame(width: max(2, width * (fraction(opening.end) - fraction(opening.start))))
                        .offset(x: width * fraction(opening.start))
                }
                Capsule().fill(Theme.accentGradient).frame(width: width * fraction(current))
            }
            .frame(height: height)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: isScrubbing ? 22 : 14, height: isScrubbing ? 22 : 14)
                    .shadow(color: Theme.pink.opacity(0.6), radius: 6)
                    .offset(x: width * fraction(current) - (isScrubbing ? 11 : 7))
            }
            .overlay(alignment: .leading) {
                if isScrubbing {
                    Text(TimeFormat.string(current))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .fixedSize()
                        .offset(x: min(max(0, width * fraction(current) - 28), max(0, width - 64)), y: -34)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing { onBegin() }
                        onChange(Double(value.location.x / max(1, width)))
                    }
                    .onEnded { _ in onEnd() }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isScrubbing)
        }
        .frame(height: 28)
    }
}
