import Foundation

/// Что именно ищется в расписании: группа, преподаватель или аудитория.
///
/// Значения `rawValue` совпадают с `scheduleTarget` из API — так ответ сервера
/// декодируется без таблицы перекодировки.
enum TargetKind: Int, Codable, CaseIterable, Sendable {
    case group = 1
    case teacher = 2
    case auditorium = 3

    /// Известное значение из API; неизвестное считаем группой.
    /// Неизвестный код не должен ронять поиск — фид может расшириться.
    static func from(id: Int) -> TargetKind {
        TargetKind(rawValue: id) ?? .group
    }

    /// Название категории для бейджа в результатах поиска.
    var displayName: String {
        switch self {
        case .group:      String(localized: "target.kind.group")
        case .teacher:    String(localized: "target.kind.teacher")
        case .auditorium: String(localized: "target.kind.auditorium")
        }
    }

    /// Сегмент пути в эндпоинте iCal: `/ical/Group/5539`.
    var pathName: String {
        switch self {
        case .group:      "Group"
        case .teacher:    "Teacher"
        case .auditorium: "Auditorium"
        }
    }
}

/// Расписание, которое можно открыть: группа, преподаватель или аудитория.
struct ScheduleTarget: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    /// Короткое имя: «ИКБО-10-25», «Мирзоян Д. И.».
    let title: String
    /// Полное имя: «Мирзоян Дмитрий Ильич».
    let fullTitle: String
    let kind: TargetKind

    /// Подпись для списка сохранённых расписаний.
    var displayTitle: String { title.isEmpty ? fullTitle : title }

    private enum CodingKeys: String, CodingKey {
        case id, title, fullTitle, kind
    }

    init(id: Int, title: String, fullTitle: String, kind: TargetKind) {
        self.id = id
        self.title = title
        self.fullTitle = fullTitle
        self.kind = kind
    }

    /// Ответ API: `{ id, targetTitle, fullTitle, scheduleTarget }`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        fullTitle = (try? container.decode(String.self, forKey: .fullTitle)) ?? title
        let rawKind = (try? container.decode(Int.self, forKey: .kind)) ?? 1
        kind = TargetKind.from(id: rawKind)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(fullTitle, forKey: .fullTitle)
        try container.encode(kind.rawValue, forKey: .kind)
    }
}

/// Маркер недели из фида: событие «N неделя» на дату понедельника.
///
/// Это источник истины для нумерации недель. Университет публикует их сам,
/// поэтому праздники и переносы начала семестра учитываются автоматически —
/// в отличие от расчёта по захардкоженным датам.
struct WeekMarker: Hashable, Codable, Sendable {
    let number: Int
    /// Понедельник недели (после выравнивания, см. `WeekCalculator`).
    let monday: DayKey
}

/// Одно занятие как правило повторения: «каждую вторую неделю по понедельникам
/// в 09:00, до 30 декабря, кроме 31 августа и 21 декабря».
///
/// В отличие от оригинала, где расписание разворачивалось в плоский список дат
/// на весь семестр, здесь храним правило. Кэш остаётся компактным, а слоты дня
/// вычисляются из окна дат — и расписание не «застывает» после пяти месяцев.
struct Occurrence: Hashable, Codable, Sendable {
    /// UID из фида. Только для отладки и стабильности порядка — **не** для
    /// ключей заметок: UID пересобирается при регенерации фида.
    let id: String
    let subject: String
    let type: LessonType
    let teachers: [String]
    let rooms: [String]
    let groups: [String]
    let bell: Int
    let start: TimeOfDay
    let end: TimeOfDay
    /// Дата первого занятия (DTSTART).
    let firstDay: DayKey
    /// Шаг повторения в неделях: 1 — каждую неделю, 2 — через неделю.
    let intervalWeeks: Int
    /// Последний день действия правила (UNTIL). nil — до конца окна.
    let until: DayKey?
    /// Исключённые даты (EXDATE).
    let excludedDays: Set<DayKey>

    /// Все даты, в которые это правило даёт занятие, в пределах `limit`.
    ///
    /// `limit` обязателен: правило без UNTIL бесконечно, а UI всегда работает
    /// с конечным окном.
    func days(upTo limit: DayKey) -> [DayKey] {
        guard intervalWeeks > 0 else { return [] }
        let horizon = until.map { min($0, limit) } ?? limit
        guard firstDay <= horizon else { return [] }

        var result: [DayKey] = []
        var current = firstDay
        while current <= horizon {
            if !excludedDays.contains(current) {
                result.append(current)
            }
            current = current.adding(days: 7 * intervalWeeks)
        }
        return result
    }
}

/// Занятие на конкретную дату — то, что рисуется в ленте дня.
struct Lesson: Identifiable, Hashable, Sendable {
    /// Идентификатор правила из фида.
    let occurrenceID: String
    let day: DayKey
    let bell: Int
    let start: TimeOfDay
    let end: TimeOfDay
    let subject: String
    let type: LessonType
    let teachers: [String]
    let rooms: [String]
    let groups: [String]

    /// Стабильный идентификатор в пределах дня: правило + дата.
    var id: String { "\(occurrenceID)@\(day)" }

    /// Дистанционная пара: в фиде аудитория приходит строкой «СДО»
    /// (сайт вуза online-edu.mirea.ru), а не номером. Сравнение без регистра —
    /// фид писали и «СДО», и «сдо».
    var isRemote: Bool {
        rooms.contains { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("СДО") == .orderedSame }
    }

    /// Аудитории без дистанционного маркера.
    var physicalRooms: [String] {
        rooms.filter { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("СДО") != .orderedSame }
    }

    var durationMinutes: Int {
        end.minutesSinceMidnight - start.minutesSinceMidnight
    }
}

/// Слот дня: пара или окно без пары.
///
/// Один слот может содержать несколько занятий — например, две подгруппы
/// одной группы в одно время. Схлопывать их в один нельзя: у них разные
/// преподаватели и аудитории.
enum DaySlot: Identifiable, Sendable {
    case active(bell: Int, start: TimeOfDay, end: TimeOfDay, lessons: [Lesson])
    case empty(bell: Int, start: TimeOfDay, end: TimeOfDay)

    var bell: Int {
        switch self {
        case .active(let bell, _, _, _): bell
        case .empty(let bell, _, _): bell
        }
    }

    var start: TimeOfDay {
        switch self {
        case .active(_, let start, _, _): start
        case .empty(_, let start, _): start
        }
    }

    var end: TimeOfDay {
        switch self {
        case .active(_, _, let end, _): end
        case .empty(_, _, let end): end
        }
    }

    var lessons: [Lesson] {
        switch self {
        case .active(_, _, _, let lessons): lessons
        case .empty: []
        }
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var id: String {
        switch self {
        case .active(let bell, _, _, let lessons):
            "active-\(bell)-" + lessons.map(\.id).joined(separator: "|")
        case .empty(let bell, _, _):
            "empty-\(bell)"
        }
    }
}