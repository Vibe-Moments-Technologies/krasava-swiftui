import Foundation

/// Сборка ленты дня из правил повторения.
///
/// Разделение обязанностей: парсер даёт правила (`Occurrence`), билдер —
/// конкретные дни и слоты. Это позволяет держать кэш компактным (правил ~100
/// вместо тысяч дат) и считать любое окно дат на лету.
struct ScheduleBuilder: Sendable {
    /// Окно дат, в котором приложение умеет показывать расписание.
    /// Вперёд берём с запасом на семестр, назад — чтобы можно было листнуть
    /// в прошлое и посмотреть, что было.
    struct Window: Sendable {
        var from: DayKey
        var to: DayKey

        init(from: DayKey, to: DayKey) {
            self.from = from
            self.to = to
        }

        /// Окно вокруг даты: 14 дней назад и 120 вперёд.
        static func around(_ today: DayKey) -> Window {
            Window(from: today.adding(days: -14), to: today.adding(days: 120))
        }
    }

    private let occurrences: [Occurrence]
    private let window: Window

    init(occurrences: [Occurrence], window: Window) {
        self.occurrences = occurrences
        self.window = window
    }

    /// Все занятия по дням в пределах окна.
    func lessonsByDay() -> [DayKey: [Lesson]] {
        var result: [DayKey: [Lesson]] = [:]
        for occurrence in occurrences {
            for day in occurrence.days(upTo: window.to) where day >= window.from {
                result[day, default: []].append(lesson(from: occurrence, on: day))
            }
        }
        for key in result.keys {
            result[key]?.sort { lhs, rhs in
                if lhs.bell != rhs.bell { return lhs.bell < rhs.bell }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.subject < rhs.subject
            }
        }
        return result
    }

    /// Слоты конкретного дня, сгруппированные по номеру пары.
    ///
    /// `showEmpty` добавляет окна между занятиями: без них лента «прыгает» с
    /// первой пары на пятую, и непонятно, что между ними перерыв.
    func slots(for day: DayKey, lessons: [Lesson], showEmpty: Bool) -> [DaySlot] {
        let dayLessons = lessons.filter { $0.day == day }
        guard !dayLessons.isEmpty else {
            guard showEmpty, day.isoWeekday() != 7 else { return [] }
            return Bells.all.map {
                DaySlot.empty(bell: $0.number, start: $0.start, end: $0.end)
            }
        }

        let grouped = Dictionary(grouping: dayLessons, by: \.bell)
        guard showEmpty else {
            return grouped.keys.sorted().compactMap { bell in
                guard let items = grouped[bell] else { return nil }
                return DaySlot.active(
                    bell: bell,
                    start: items[0].start,
                    end: items[0].end,
                    lessons: items
                )
            }
        }

        let lastBell = max(grouped.keys.max() ?? 7, 7)
        return (1...lastBell).compactMap { bell in
            if let items = grouped[bell] {
                return DaySlot.active(bell: bell, start: items[0].start, end: items[0].end, lessons: items)
            }
            guard let template = Bells.bell(number: bell) else { return nil }
            return DaySlot.empty(bell: bell, start: template.start, end: template.end)
        }
    }

    /// Дни окна, в которых есть занятия, — для точек в мини-календаре.
    func daysWithLessons() -> Set<DayKey> {
        Set(occurrences.flatMap { $0.days(upTo: window.to) }.filter { $0 >= window.from })
    }

    private func lesson(from occurrence: Occurrence, on day: DayKey) -> Lesson {
        Lesson(
            occurrenceID: occurrence.id,
            day: day,
            bell: occurrence.bell,
            start: occurrence.start,
            end: occurrence.end,
            subject: occurrence.subject,
            type: occurrence.type,
            teachers: occurrence.teachers,
            rooms: occurrence.rooms,
            groups: occurrence.groups
        )
    }
}