import SwiftUI
import UIKit

/// Colours, gradients and metrics shared by every screen.
enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.055)
    static let elevated = Color(red: 0.075, green: 0.075, blue: 0.105)
    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.11)
    static let stroke = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.4)

    static let pink = Color(red: 1.0, green: 0.33, blue: 0.53)
    static let violet = Color(red: 0.55, green: 0.38, blue: 1.0)

    static let accentGradient = LinearGradient(colors: [pink, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroFade = LinearGradient(
        stops: [
            .init(color: background.opacity(0), location: 0),
            .init(color: background.opacity(0.55), location: 0.55),
            .init(color: background, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardRadius: CGFloat = 14
    static let posterRadius: CGFloat = 12

    static func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...: return Color(red: 0.3, green: 0.85, blue: 0.5)
        case 7..<8: return Color(red: 0.98, green: 0.78, blue: 0.25)
        default: return Color(red: 1.0, green: 0.55, blue: 0.3)
        }
    }

    /// System bars that match the dark design.
    static func applyAppearance() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithDefaultBackground()
        tabBar.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        tabBar.backgroundColor = UIColor(background).withAlphaComponent(0.6)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 32, weight: .heavy),
        ]
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        scrolled.titleTextAttributes = [.foregroundColor: UIColor.white]
        scrolled.largeTitleTextAttributes = navigation.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

extension View {
    /// Dark screen background used under every tab.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    func card(radius: CGFloat = Theme.cardRadius) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke))
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

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.pink.opacity(0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, circle ? 0 : 16)
            .frame(minWidth: circle ? 50 : nil, minHeight: 50)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: circle ? 25 : 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: circle ? 25 : 16, style: .continuous).strokeBorder(Theme.stroke))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: Chips

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
        .foregroundStyle(isSelected ? Color.white : (isDisabled ? Theme.tertiaryText : Theme.secondaryText))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            Capsule().fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
        }
        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.stroke))
        .contentShape(Capsule())
    }
}

/// Small rounded label: "TV", "2023", "Онгоинг".
struct Tag: View {
    let text: String
    var color: Color = .white
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(filled ? Color.black : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? color : color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.heavy))
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
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
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
