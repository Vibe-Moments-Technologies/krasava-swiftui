import Foundation

/// Доступ к общему контейнеру приложения и виджета.
///
/// Виджет — отдельный процесс, и общаться с ним можно только через App Group.
/// При сборке с обычной подписью Apple группа выдаётся системой; при
/// переподписи сторонним сертификатом (side­load) контейнер может быть
/// недоступен — тогда приложение продолжает работать, а виджет честно
/// показывает «нет данных», вместо того чтобы падать.
enum AppGroup {
    static let identifier = "group.ru.vibemoments.krasavaswiftui"
    static let snapshotKey = "widget_payload"

    /// Контейнер группы, если он реально доступен этому процессу.
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static var isAvailable: Bool { defaults() != nil }
}

/// Компактный снимок расписания для виджетов.
///
/// Виджет **никогда не ходит в сеть**: расширение живёт в жёстких лимитах по
/// памяти и времени, а расписание всё равно обновляет приложение. Поэтому
/// приложение при любом изменении данных пишет этот снимок в App Group,
/// а виджет только читает его и пересчитывает отображение.
struct WidgetSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1
    /// На сколько дней вперёд пишем занятия: неделя с запасом покрывает все
    /// виджеты, включая «неделя + пары».
    static let daysAhead = 8

    var schemaVersion: Int = WidgetSnapshot.currentSchemaVersion
    var generatedAt: Date
    var targetTitle: String?
    var lessons: [WidgetLesson]
    /// Цвета типов, переопределённые пользователем. Ключ — `LessonType.rawValue`.
    /// Пусто — виджет рисует свою системную палитру.
    var typeColors: [String: UInt32]

    var isCompatible: Bool { schemaVersion == Self.currentSchemaVersion }
}

/// Занятие в снимке для виджета.
struct WidgetLesson: Codable, Hashable, Identifiable, Sendable {
    /// Стабильный идентификатор пары: правило + дата. Нужен, чтобы две
    /// одинаковые пары подряд оставались разными записями.
    let id: String
    /// `yyyy-MM-dd` — строкой, чтобы виджет не зависел от часового пояса
    /// при декодировании дат.
    let date: String
    let bell: Int
    /// `HH:mm` локального времени вуза.
    let start: String
    let end: String
    let subject: String
    let type: String
    let room: String
    let teacher: String
    let groups: [String]

    var isRemote: Bool {
        room.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("СДО") == .orderedSame
    }

    /// Уникальные группы занятия — для индикатора совместного занятия.
    var groupCount: Int { Set(groups).count }
}

/// Сборка и запись снимка.
enum WidgetSnapshotWriter {
    static func makeSnapshot(
        targetTitle: String?,
        lessons: [Lesson],
        overrides: UserOverrides,
        today: DayKey,
        now: Date = Date()
    ) -> WidgetSnapshot {
        let horizon = today.adding(days: WidgetSnapshot.daysAhead - 1)
        let relevant = lessons
            .filter { $0.day >= today && $0.day <= horizon }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day { return lhs.day < rhs.day }
                if lhs.bell != rhs.bell { return lhs.bell < rhs.bell }
                return lhs.subject < rhs.subject
            }

        return WidgetSnapshot(
            generatedAt: now,
            targetTitle: targetTitle,
            lessons: relevant.map { lesson in
                WidgetLesson(
                    id: lesson.id,
                    date: lesson.day.storageKey,
                    bell: lesson.bell,
                    start: lesson.start.description,
                    end: lesson.end.description,
                    subject: lesson.subject,
                    type: overrides.effectiveType(for: lesson).rawValue,
                    room: lesson.rooms.joined(separator: ", "),
                    teacher: lesson.teachers.joined(separator: ", "),
                    groups: lesson.groups
                )
            },
            typeColors: overrides.typeColors.mapValues(\.hex)
        )
    }

    /// Запись снимка в общий контейнер. Молча ничего не делает, если App Group
    /// недоступна: приложение обязано работать и без виджета.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = AppGroup.defaults() else { return }
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: AppGroup.snapshotKey)
    }

    static func clear() {
        AppGroup.defaults()?.removeObject(forKey: AppGroup.snapshotKey)
    }
}