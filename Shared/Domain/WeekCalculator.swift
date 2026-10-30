import Foundation

/// Номер недели семестра и её чётность.
///
/// Источник истины — маркеры «N неделя» из фида: вуз публикует их сам, поэтому
/// переносы начала семестра и праздничные недели учитываются без нашего участия.
/// Расчёт по датам — только фолбэк, пока фид не разобран или не покрывает дату.
struct WeekCalculator: Sendable {
    private let markers: [WeekMarker]

    init(markers: [WeekMarker]) {
        self.markers = markers
            .map { WeekMarker(number: $0.number, monday: $0.monday.mondayOfWeek()) }
            .sorted { $0.monday < $1.monday }
    }

    var weekCount: Int { markers.count }

    /// Номер недели для даты: из маркеров, иначе расчётный фолбэк.
    /// Никогда не возвращает меньше 1 — нулевой недели не бывает.
    func weekNumber(for day: DayKey) -> Int {
        if let fromFeed = weekNumberFromMarkers(for: day) {
            return max(fromFeed, 1)
        }
        return max(computedWeekNumber(for: day), 1)
    }

    func isEvenWeek(_ day: DayKey) -> Bool {
        weekNumber(for: day) % 2 == 0
    }

    /// Понедельник учебной недели, в которую попадает дата.
    func monday(of day: DayKey) -> DayKey {
        day.mondayOfWeek()
    }

    /// Границы семестра по маркерам: от первого понедельника до конца
    /// последней недели. nil, если маркеров нет.
    var semesterRange: ClosedRange<DayKey>? {
        guard let first = markers.first, let last = markers.last else { return nil }
        return first.monday...(last.monday.adding(days: 6))
    }

    private func weekNumberFromMarkers(for day: DayKey) -> Int? {
        // Маркеров ~18 на семестр: линейный поиск дешевле бинарного и читается проще.
        guard let marker = markers.last(where: { $0.monday <= day }),
              day < marker.monday.adding(days: 7) else { return nil }
        return marker.number
    }

    /// Фолбэк-расчёт от начала семестра.
    ///
    /// Семестр начинается 9 февраля (весенний) или 1 сентября (осенний).
    /// Отсчёт идёт от понедельника той недели: иначе неполная первая неделя
    /// съедала бы номер у всех последующих — 1 сентября 2026 приходится на
    /// вторник, и без выравнивания весь семестр сдвинулся бы на неделю.
    private func computedWeekNumber(for day: DayKey) -> Int {
        let semesterStart: DayKey
        if (2...8).contains(day.month) {
            semesterStart = DayKey(year: day.year, month: 2, day: 9)
        } else {
            let fallYear = day.month == 1 ? day.year - 1 : day.year
            semesterStart = DayKey(year: fallYear, month: 9, day: 1)
        }
        let firstMonday = semesterStart.mondayOfWeek()
        let distance = firstMonday.days(until: day)
        return distance >= 0 ? distance / 7 + 1 : 1
    }
}