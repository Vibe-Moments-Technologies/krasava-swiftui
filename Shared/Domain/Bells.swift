import Foundation

/// Сетка звонков РТУ МИРЭА.
///
/// Вузовская сетка фиксированная, поэтому она живёт в коде, а не в фиде:
/// фид присылает только время пары, а номера пар нужны для ключей уведомлений
/// и заметок даже для пар, которых в расписании нет (пустые пары).
struct Bell: Hashable, Sendable {
    let number: Int
    let start: TimeOfDay
    let end: TimeOfDay
}

enum Bells {
    static let all: [Bell] = [
        Bell(number: 1, start: TimeOfDay(hour: 9,  minute: 0),  end: TimeOfDay(hour: 10, minute: 30)),
        Bell(number: 2, start: TimeOfDay(hour: 10, minute: 40), end: TimeOfDay(hour: 12, minute: 10)),
        Bell(number: 3, start: TimeOfDay(hour: 12, minute: 40), end: TimeOfDay(hour: 14, minute: 10)),
        Bell(number: 4, start: TimeOfDay(hour: 14, minute: 20), end: TimeOfDay(hour: 15, minute: 50)),
        Bell(number: 5, start: TimeOfDay(hour: 16, minute: 20), end: TimeOfDay(hour: 17, minute: 50)),
        Bell(number: 6, start: TimeOfDay(hour: 18, minute: 0),  end: TimeOfDay(hour: 19, minute: 30)),
        Bell(number: 7, start: TimeOfDay(hour: 19, minute: 40), end: TimeOfDay(hour: 21, minute: 10)),
    ]

    static func bell(number: Int) -> Bell? {
        all.first { $0.number == number }
    }

    /// Номер пары по времени начала.
    ///
    /// Границы взяты по часу, как в оригинале: фид может отдать 08:50 (сдвиг
    /// перед праздниками), и такая пара всё равно должна попасть в первую.
    /// Последнее правило `else` — не «1 по умолчанию», а «ближайшая сетка»:
    /// незнакомое время привязываем к ближайшей паре, чтобы занятие не
    /// потерялось при группировке.
    static func bellNumber(for start: TimeOfDay) -> Int {
        switch start.hour {
        case 8, 9:      return 1
        case 10, 11:    return 2
        case 12, 13:    return 3
        case 14, 15:    return 4
        case 16, 17:    return 5
        case 18:        return 6
        case 19, 20, 21: return 7
        default:        return nearestBell(to: start)
        }
    }

    private static func nearestBell(to start: TimeOfDay) -> Int {
        let minutes = start.minutesSinceMidnight
        return all.min { lhs, rhs in
            abs(lhs.start.minutesSinceMidnight - minutes) < abs(rhs.start.minutesSinceMidnight - minutes)
        }?.number ?? 1
    }

    /// Перемена между двумя парами в минутах; 0, если её нет или данные битые.
    static func breakMinutes(from end: TimeOfDay, to next: TimeOfDay) -> Int {
        let diff = next.minutesSinceMidnight - end.minutesSinceMidnight
        return diff > 0 ? diff : 0
    }
}