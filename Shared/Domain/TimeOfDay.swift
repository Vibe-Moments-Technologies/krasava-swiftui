import Foundation

/// Время суток без даты и без часового пояса: «09:00».
///
/// Отдельный тип, а не `Date`, потому что расписание приходит как локальное
/// настенное время вуза. Если хранить это как `Date`, любая смена пояса
/// устройства сдвигала бы пары — а пара в 09:00 остаётся парой в 09:00.
struct TimeOfDay: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Разбор `HH:mm` или `HHmm`. Возвращает nil на мусоре, а не 00:00:
    /// иначе битая строка фида молча превратилась бы в полночь.
    init?(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        let hourText: Substring
        let minuteText: Substring
        switch parts.count {
        case 2:
            hourText = parts[0]
            minuteText = parts[1]
        case 1 where trimmed.count == 4:
            hourText = trimmed.prefix(2)
            minuteText = trimmed.suffix(2)
        default:
            return nil
        }
        guard let hour = Int(hourText), let minute = Int(minuteText),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    var description: String {
        String(format: "%02d:%02d", hour, minute)
    }
}