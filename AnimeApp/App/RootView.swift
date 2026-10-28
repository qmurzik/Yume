import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Главная", systemImage: "house") }
            CatalogView()
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }
            SearchView()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            ScheduleView()
                .tabItem { Label("Расписание", systemImage: "calendar") }
            LibraryView()
                .tabItem { Label("Моё", systemImage: "person.crop.circle") }
        }
    }
}
