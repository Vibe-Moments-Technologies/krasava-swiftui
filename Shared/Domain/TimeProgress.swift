import Foundation

/// Общий расчёт прогресса временных интервалов.
///
/// Вынесен из представлений: одинаковые правила нужны карточке пары, пустой
/// паре и перемене. Раньше каждая рисовала прогресс своим способом, и пустая
/// пара вообще осталась без индикатора.
enum TimeProgress {
    /// Прогресс интервала от 0 до 1. `nil`, если интервал ещё не начался,
    /// уже закончился или имеет нулевую длину.
    static func fraction(
        start: TimeOfDay,
        end: TimeOfDay,
        nowMinutes: Int
    ) -> Double? {
        let from = start.minutesSinceMidnight
        let to = end.minutesSinceMidnight
        guard to > from, nowMinutes >= from, nowMinutes < to else { return nil }
        return Double(nowMinutes - from) / Double(to - from)
    }

    /// Минуты от полуночи в календаре устройства.
    static func minutes(
        of date: Date = Date(),
        calendar: Calendar = ScheduleClock.calendar
    ) -> Int {
        calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
    }

    /// Прогресс на текущий момент.
    static func fractionNow(
        start: TimeOfDay,
        end: TimeOfDay,
        date: Date = Date(),
        calendar: Calendar = ScheduleClock.calendar
    ) -> Double? {
        fraction(start: start, end: end, nowMinutes: minutes(of: date, calendar: calendar))
    }
}