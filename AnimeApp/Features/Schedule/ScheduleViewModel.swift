import Combine
import Foundation

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var entries: Loadable<[ScheduleEntry]> = .idle
    @Published var day: Int = ScheduleViewModel.todayWeekday()

    private let services: AppServices

    init(services: AppServices = .live) {
        self.services = services
    }

    static let dayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    static let fullDayNames = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]

    /// ISO weekday, Monday = 1.
    static func todayWeekday(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date) // Sunday = 1
        return (weekday + 5) % 7 + 1
    }

    /// Calendar date of the given ISO weekday in the current week.
    static func date(of weekday: Int, from today: Date = Date(), calendar: Calendar = .current) -> Date {
        let offset = weekday - todayWeekday(today, calendar: calendar)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    func entries(for day: Int) -> [ScheduleEntry] {
        (entries.value ?? []).filter { $0.weekday == day }
    }

    func loadIfNeeded() async {
        if entries.isIdle { await load() }
    }

    func load() async {
        if entries.value == nil { entries = .loading }
        do {
            entries = .loaded(try await services.aniLibria.weekSchedule())
        } catch is CancellationError {
        } catch {
            entries = .failed(error)
        }
    }
}
