import Foundation

/// Ключи для заметок.
///
/// Здесь исправлен баг оригинального приложения, из-за которого заметки
/// стирались при каждом обновлении расписания. Там заметка была привязана к
/// `lesson.id`, а он собирался из `UID` события фида, который пересобирается
/// при регенерации iCal. Новый UID — новый ключ — заметка «теряется».
///
/// Правило Lite: в ключе участвует только то, что пользователь видит сам —
/// расписание, дата, номер пары, предмет. UID из фида в ключ не входит никогда.
enum NoteKeys {

    /// Заметка к конкретной паре: расписание + день + номер пары.
    ///
    /// Время в ключ не входит намеренно: перенос пары с 12:40 на 12:45 —
    /// всё ещё та же пара, и заметка должна остаться с ней.
    static func lesson(targetID: Int, day: DayKey, bell: Int) -> String {
        "lesson:\(targetID):\(day.storageKey):\(bell)"
    }

    /// Заметка к предмету: расписание + нормализованное название.
    static func subject(targetID: Int, subject: String) -> String {
        "subject:\(targetID):\(normalizeSubject(subject))"
    }

    /// Нормализация названия предмета для ключа.
    ///
    /// `ё` → `е` и схлопывание пробелов обязательны: фид пишет
    /// «Конфигурационное  управление» с двойным пробелом после регенерации.
    static func normalizeSubject(_ subject: String) -> String {
        subject
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Заметка пользователя.
struct LessonNote: Codable, Hashable, Identifiable, Sendable {
    /// Ключ из `NoteKeys`. Хранится строкой, чтобы один файл мог держать
    /// заметки и к парам, и к предметам.
    let key: String
    var text: String
    var updatedAt: Date

    var id: String { key }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}