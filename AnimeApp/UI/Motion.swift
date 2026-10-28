import SwiftUI

enum Motion {
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.86)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let fade = Animation.easeInOut(duration: 0.3)
}

extension Loadable {
    /// Equatable stand-in for animating between loading, error and content.
    var phaseKey: Int {
        switch self {
        case .idle: return 0
        case .loading: return 1
        case .loaded: return 2
        case .failed: return 3
        }
    }
}

/// Fades and lifts a view in the first time it appears; items early in a list are staggered.
struct AppearEffect: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .scaleEffect(shown ? 1 : 0.96, anchor: .bottom)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.spring.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func appear(_ index: Int = 0) -> some View {
        modifier(AppearEffect(delay: index < 12 ? Double(index) * 0.045 : 0))
    }
}

// MARK: Zoom transition (iOS 18+)

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Namespace of the current navigation stack, shared by sources and destinations.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

private struct ZoomSource: ViewModifier {
    let id: String?
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    let id: String?
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// The view a title screen zooms out of (iOS 18+; a regular push before that).
    func zoomSource(_ id: String?) -> some View { modifier(ZoomSource(id: id)) }
    func zoomDestination(_ id: String?) -> some View { modifier(ZoomDestination(id: id)) }
}

/// Navigation stack that provides the zoom namespace to everything inside it.
struct ZoomNavigationStack<Content: View>: View {
    @Namespace private var namespace
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .animeNavigation()
        }
        .environment(\.zoomNamespace, namespace)
    }
}
