import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, catalog, search, schedule, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .catalog: return "Каталог"
        case .search: return "Поиск"
        case .schedule: return "Неделя"
        case .library: return "Моё"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .catalog: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .schedule: return "calendar"
        case .library: return "bookmark"
        }
    }

    /// Filled variant where SF Symbols has one.
    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .catalog: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .schedule: return "calendar"
        case .library: return "bookmark.fill"
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            tabContent(HomeView(), .home)
            tabContent(CatalogView(), .catalog)
            tabContent(SearchView(), .search)
            tabContent(ScheduleView(), .schedule)
            tabContent(LibraryView(), .library)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $tab)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func tabContent<Content: View>(_ content: Content, _ item: AppTab) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            // Room for the floating bar so the last row isn't hidden under it.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 62) }
            .tag(item)
    }
}

/// Ink capsule with the selected tab stamped in vermilion.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { item in
                Button {
                    guard selection != item else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selection == item ? item.selectedIcon : item.icon)
                            .font(.system(size: 17, weight: .semibold))
                        if selection == item {
                            Text(item.title)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .foregroundStyle(selection == item ? Theme.cream : Theme.secondaryText)
                    .padding(.horizontal, selection == item ? 14 : 0)
                    .frame(maxWidth: selection == item ? nil : .infinity, minHeight: 46)
                    .background {
                        if selection == item {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.accentFill)
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Theme.elevated.opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        }
        .frame(maxWidth: 520)
    }
}
