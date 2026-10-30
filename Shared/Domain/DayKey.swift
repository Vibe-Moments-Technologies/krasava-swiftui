import Foundation

/// Календарная дата без времени: 2026-09-14.
///
/// Своя структура вместо `Date`, потому что расписание живёт в календаре вуза,
/// а не в UTC-моменте. `Date` — это точка на временной шкале; «пара 14 сентября»
/// от смены часового пояса меняться не должна. Побочный плюс: сравнение, хэш и
/// Codable бесплатны, а тесты не зависят от системной зоны.
struct DayKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Разбор даты из iCal и из служебных блоков фида.
    ///
    /// Фид использует два разных формата в одном документе:
    ///  * компактный `20260914T090000` — у `DTSTART`/`EXDATE`/`UNTIL`;
    ///  * ISO с дефисами `2026-08-31T21:00:00Z` — у `X-SV-START`/`X-SV-END`.
    ///
    /// Поэтому сначала выбрасываем всё, кроме цифр, и берём первые восемь:
    /// для обоих форматов это ровно `yyyyMMdd`. Время и зона отбрасываются —
    /// день у занятия определяется календарной датой вуза.
    init?(iso: String) {
        let digits = iso.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        let chars = Array(digits.prefix(8))
        guard let year = Int(String(chars[0..<4])),
              let month = Int(String(chars[4..<6])),
              let day = Int(String(chars[6..<8])),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(_ date: Date, calendar: Calendar = ScheduleClock.calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    func date(calendar: Calendar = ScheduleClock.calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Сдвиг на N дней через календарь: арифметика «+1» к номеру дня сломалась
    /// бы на переходе между месяцами, а `86400` секунд — на переходе на летнее
    /// время.
    func adding(days: Int, calendar: Calendar = ScheduleClock.calendar) -> DayKey {
        guard let base = date(calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: base) else {
            return self
        }
        return DayKey(shifted, calendar: calendar)
    }

    /// ISO-день недели: 1 — понедельник, 7 — воскресенье.
    ///
    /// Считаем от системного `weekday` (1 = воскресенье) формулой, а не через
    /// `calendar.firstWeekday`: тот зависит от локали устройства, и на
    /// американской локали неделя начиналась бы с воскресенья.
    func isoWeekday(calendar: Calendar = ScheduleClock.calendar) -> Int {
        guard let date = date(calendar: calendar) else { return 1 }
        let systemWeekday = calendar.component(.weekday, from: date) // 1 = Вс
        return (systemWeekday + 5) % 7 + 1
    }

    /// Понедельник недели, в которую попадает дата.
    func mondayOfWeek(calendar: Calendar = ScheduleClock.calendar) -> DayKey {
        adding(days: -(isoWeekday(calendar: calendar) - 1), calendar: calendar)
    }

    /// Число дней от `self` до `other` (положительное, если `other` позже).
    func days(until other: DayKey, calendar: Calendar = ScheduleClock.calendar) -> Int {
        guard let from = date(calendar: calendar), let to = other.date(calendar: calendar) else {
            return 0
        }
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Строка для ключей хранилища заметок: без времени и пояса.
    var storageKey: String { description }
}

/// Календарь и «сегодня» в одном месте.
///
/// Отдельная точка нужна, чтобы тесты могли подменить текущую дату, а весь
/// остальной код не собирал `Calendar` вручную в десяти местах.
enum ScheduleClock {
    /// Григорианский календарь с текущим поясом устройства.
    /// Первый день недели — понедельник: расписание вуза всегда недельное.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.locale = .current
        return calendar
    }

    static var timeZone: TimeZone { .current }

    static func today(now: Date = Date()) -> DayKey {
        DayKey(now, calendar: calendar)
    }
}