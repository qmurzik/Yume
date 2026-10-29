import SwiftUI
import UIKit

/// "Ink & vermilion": warm ink backgrounds, one vermilion accent like a hanko seal,
/// cream for emphasis and gold for scores. Display type is Unbounded.
enum Theme {
    static let background = Color(red: 0.055, green: 0.051, blue: 0.067)
    static let elevated = Color(red: 0.094, green: 0.086, blue: 0.11)
    static let surface = Color.white.opacity(0.05)
    static let surfaceStrong = Color.white.opacity(0.09)
    static let stroke = Color.white.opacity(0.08)
    static let secondaryText = Color(red: 0.96, green: 0.91, blue: 0.85).opacity(0.62)
    static let tertiaryText = Color(red: 0.96, green: 0.91, blue: 0.85).opacity(0.38)

    /// Vermilion, the one brand colour.
    static let accent = Color(red: 1.0, green: 0.31, blue: 0.2)
    static let accentDeep = Color(red: 0.86, green: 0.2, blue: 0.13)
    static let cream = Color(red: 0.96, green: 0.91, blue: 0.85)
    static let gold = Color(red: 0.93, green: 0.72, blue: 0.33)

    /// Almost flat vermilion with a slight fall-off, like ink on paper.
    static let accentFill = LinearGradient(colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)
    static let heroFade = LinearGradient(
        stops: [
            .init(color: background.opacity(0), location: 0),
            .init(color: background.opacity(0.6), location: 0.55),
            .init(color: background, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardRadius: CGFloat = 12
    static let posterRadius: CGFloat = 6

    static func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...: return gold
        case 7..<8: return cream
        default: return cream.opacity(0.6)
        }
    }

    /// System bars that match the design; the tab bar itself is custom (`FloatingTabBar`).
    static func applyAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor(cream),
            .font: UIFont(name: "Unbounded-Black", size: 30) ?? .systemFont(ofSize: 32, weight: .heavy),
        ]
        navigation.titleTextAttributes = [
            .foregroundColor: UIColor(cream),
            .font: UIFont(name: "Unbounded-Bold", size: 16) ?? .systemFont(ofSize: 17, weight: .semibold),
        ]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        scrolled.backgroundColor = UIColor(background).withAlphaComponent(0.55)
        scrolled.shadowColor = .clear
        scrolled.titleTextAttributes = navigation.titleTextAttributes
        scrolled.largeTitleTextAttributes = navigation.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().tintColor = UIColor(cream)
    }
}

extension Font {
    enum DisplayWeight: String {
        case medium = "Medium", bold = "Bold", black = "Black"
    }

    /// Unbounded display face; scales with Dynamic Type.
    static func display(_ size: CGFloat, _ weight: DisplayWeight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Unbounded-\(weight.rawValue)", size: size, relativeTo: style)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

extension View {
    /// Ink background with faint grain, used under every screen.
    func screenBackground() -> some View {
        background {
            ZStack {
                Theme.background
                GrainOverlay(opacity: 0.05)
            }
            .ignoresSafeArea()
        }
    }

    func card(radius: CGFloat = Theme.cardRadius) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Film grain generated once with Core Image and tiled.
struct GrainOverlay: View {
    var opacity: Double = 0.08

    private static let image: UIImage? = {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let context = CIContext()
        guard let cg = context.createCGImage(mono, from: CGRect(x: 0, y: 0, width: 160, height: 160)) else { return nil }
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }()

    var body: some View {
        if let image = Self.image {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }
}

// MARK: Buttons

/// Gentle shrink on press for cards and tiles.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Solid vermilion, like a seal stamp.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .default).weight(.bold))
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .top) {
                // Thin highlight along the top edge.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, circle ? 0 : 16)
            .frame(minWidth: circle ? 50 : nil, minHeight: 50)
            .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: circle ? 25 : 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: circle ? 25 : 14, style: .continuous).strokeBorder(Theme.stroke))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: Chips & labels

struct Chip: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var isDisabled = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption.weight(.bold))
            }
            Text(title).lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isSelected ? Theme.cream : (isDisabled ? Theme.tertiaryText : Theme.secondaryText))
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.surface))
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isSelected ? Color.clear : Theme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Small square-cornered label: "TV", "2023", "Онгоинг".
struct Tag: View {
    let text: String
    var color: Color = Theme.cream
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(filled ? Theme.background : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(filled ? color : color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Score stamped like a hanko seal.
struct ScoreSeal: View {
    let score: Double
    var large = false

    var body: some View {
        Text(String(format: "%.1f", score))
            .font(.display(large ? 15 : 11, .black, relativeTo: .caption))
            .foregroundStyle(score >= 8 ? Theme.cream : Theme.background)
            .padding(.horizontal, large ? 9 : 6)
            .padding(.vertical, large ? 6 : 4)
            .background(score >= 8 ? Theme.accent : Theme.cream, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .rotationEffect(.degrees(-4))
    }
}

/// Section title in the display face, with a small Japanese kicker above it.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var kicker: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if let kicker {
                    Text(kicker)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.accent)
                }
                Text(title)
                    .font(.display(19, .bold, relativeTo: .title3))
                    .foregroundStyle(Theme.cream)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, kicker: String? = nil) {
        self.init(title: title, subtitle: subtitle, kicker: kicker) { EmptyView() }
    }
}

// MARK: Layout

/// Wrapping row of chips (genres, filters).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// View wrapper around `FlowLayout`.
struct Flow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: spacing).callAsFunction { content }
    }
}

// MARK: Skeletons

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.7)
                        .offset(x: phase * proxy.size.width * 1.4)
                }
                .mask { content }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct SkeletonBlock: View {
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surfaceStrong)
    }
}

struct SkeletonCard: View {
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(radius: Theme.posterRadius).aspectRatio(2 / 3, contentMode: .fit)
            SkeletonBlock(radius: 4).frame(height: 12)
            SkeletonBlock(radius: 4).frame(width: 60, height: 10)
        }
        .frame(width: width)
        .shimmering()
    }
}

struct SkeletonShelf: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in SkeletonCard(width: 132) }
            }
            .padding(.horizontal)
        }
        .disabled(true)
    }
}

struct SkeletonGrid: View {
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(0..<12, id: \.self) { _ in SkeletonCard() }
        }
        .padding(.horizontal)
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            SkeletonBlock(radius: 10).frame(width: 64, height: 92)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(radius: 4).frame(height: 14)
                SkeletonBlock(radius: 4).frame(width: 140, height: 12)
                SkeletonBlock(radius: 4).frame(width: 90, height: 10)
            }
        }
        .shimmering()
    }
}
