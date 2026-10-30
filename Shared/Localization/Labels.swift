import Foundation

/// Подписи с подстановкой чисел.
///
/// Собраны в одном месте, а не разбросаны как `Text("key \(value)")`. Причина
/// практическая: интерполяция прямо в `Text` превращает ключ каталога в
/// «key %lld», и такие ключи легко разъезжаются при правках. Здесь ключ
/// стабилен, а число подставляется через `String(format:)`.
///
/// Формулировки выбраны так, чтобы не требовать склонений по числам:
/// «Пара 3», «Неделя 9», «Перемена 10 мин». Русские формы множественного
/// числа в этом месте не нужны и только усложнили бы каталог.
enum Labels {
    static func bell(_ number: Int) -> String {
        String(format: String(localized: "lesson.bell.format"), number)
    }

    static func week(_ number: Int) -> String {
        String(format: String(localized: "week.label.format"), number)
    }

    static func breakDuration(_ minutes: Int) -> String {
        String(format: String(localized: "break.duration.format"), minutes)
    }
}