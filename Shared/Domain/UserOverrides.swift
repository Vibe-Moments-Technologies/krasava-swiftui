import Foundation

/// Цвет типа занятия, пригодный для хранения и для передачи в виджет.
///
/// Хранится как 0xRRGGBB, а не как SwiftUI `Color`: снапшот для виджета —
/// обычный JSON, и он не должен зависеть от UI-фреймворка.
struct TypeColor: Codable, Hashable, Sendable {
    var hex: UInt32

    init(hex: UInt32) {
        self.hex = hex & 0xFFFFFF
    }

    var components: (red: Double, green: Double, blue: Double) {
        (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }
}

/// Пользовательские настройки поверх данных фида.
///
/// Здесь живёт «гибридность» типов: расписание приходит со своим типом занятия,
/// но пользователь может переопределить его — у одной пары, у всего предмета
/// или просто поменять цвет типа. Иерархия приоритетов:
/// переопределение пары → переопределение предмета → тип из фида.
struct UserOverrides: Codable, Hashable, Sendable {
    /// Свои цвета типов. Отсутствие ключа — стандартный цвет типа.
    var typeColors: [String: TypeColor] = [:]
    /// Переопределение типа для всего предмета (ключ — нормализованное имя).
    var subjectTypes: [String: LessonType] = [:]
    /// Переопределение типа для одной пары (ключ — `day|bell|subject`).
    var lessonTypes: [String: LessonType] = [:]
    /// Скрытые предметы (нормализованные имена).
    var hiddenSubjects: Set<String> = []
    /// Предметы, о которых не напоминать.
    var mutedSubjects: Set<String> = []
    /// Конкретные пары, о которых не напоминать (ключ — `day|bell|subject`).
    var mutedLessons: Set<String> = []

    static let empty = UserOverrides()

    // MARK: - Ключи

    /// Ключ пары для переопределений и отключения уведомлений.
    static func lessonKey(day: DayKey, bell: Int, subject: String) -> String {
        "\(day.storageKey)|\(bell)|\(NoteKeys.normalizeSubject(subject))"
    }

    static func subjectKey(_ subject: String) -> String {
        NoteKeys.normalizeSubject(subject)
    }

    // MARK: - Тип занятия с учётом переопределений

    func effectiveType(for lesson: Lesson) -> LessonType {
        lessonTypes[Self.lessonKey(day: lesson.day, bell: lesson.bell, subject: lesson.subject)]
            ?? subjectTypes[Self.subjectKey(lesson.subject)]
            ?? lesson.type
    }

    func color(for type: LessonType) -> TypeColor? {
        typeColors[type.rawValue]
    }

    mutating func setColor(_ color: TypeColor?, for type: LessonType) {
        // nil означает «вернуть стандартный цвет» — ключ убираем совсем,
        // иначе JSON копил бы записи, равные дефолту.
        if let color {
            typeColors[type.rawValue] = color
        } else {
            typeColors.removeValue(forKey: type.rawValue)
        }
    }

    mutating func setLessonType(_ type: LessonType?, for lesson: Lesson) {
        let key = Self.lessonKey(day: lesson.day, bell: lesson.bell, subject: lesson.subject)
        if let type {
            lessonTypes[key] = type
        } else {
            lessonTypes.removeValue(forKey: key)
        }
    }

    mutating func setSubjectType(_ type: LessonType?, for subject: String) {
        let key = Self.subjectKey(subject)
        if let type {
            subjectTypes[key] = type
        } else {
            subjectTypes.removeValue(forKey: key)
        }
    }

    /// Есть ли у пары собственное переопределение типа (для пометки «вручную»).
    func hasLessonTypeOverride(for lesson: Lesson) -> Bool {
        lessonTypes[Self.lessonKey(day: lesson.day, bell: lesson.bell, subject: lesson.subject)] != nil
    }

    func hasSubjectTypeOverride(_ subject: String) -> Bool {
        subjectTypes[Self.subjectKey(subject)] != nil
    }
}

/// Какие занятия показывать.
struct VisibilityFilter: Hashable, Sendable {
    var hideAdditional: Bool = false
    var hiddenSubjects: Set<String> = []

    func isVisible(_ lesson: Lesson, overrides: UserOverrides) -> Bool {
        if hideAdditional, overrides.effectiveType(for: lesson) == .additional {
            return false
        }
        if hiddenSubjects.contains(NoteKeys.normalizeSubject(lesson.subject)) {
            return false
        }
        return true
    }

    /// Отфильтрованные занятия. Скрытие применяется и к календарю, и к diff,
    /// и к виджету, и к уведомлениям — иначе «скрытый» предмет продолжал бы
    /// всплывать в напоминаниях.
    func visible(_ lessons: [Lesson], overrides: UserOverrides) -> [Lesson] {
        lessons.filter { isVisible($0, overrides: overrides) }
    }

    func isLessonMuted(_ lesson: Lesson, overrides: UserOverrides) -> Bool {
        let key = UserOverrides.lessonKey(day: lesson.day, bell: lesson.bell, subject: lesson.subject)
        return overrides.mutedLessons.contains(key)
            || overrides.mutedSubjects.contains(UserOverrides.subjectKey(lesson.subject))
    }
}