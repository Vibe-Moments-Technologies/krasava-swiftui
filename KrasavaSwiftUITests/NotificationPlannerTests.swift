import Foundation
import Testing

/// Расчёт напоминаний.
///
/// Проверяем чистую функцию: ни `UserNotifications`, ни системных часов —
/// время и календарь приходят параметрами, поэтому тесты детерминированы.
@Suite("Напоминания")
struct NotificationPlannerTests {

    private let calendar = ScheduleClock.calendar

    private func date(_ day: DayKey, _ time: TimeOfDay) -> Date {
        calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day,
            hour: time.hour, minute: time.minute
        ))!
    }

    private func lesson(
        on day: DayKey,
        bell: Int = 1,
        start: TimeOfDay = TimeOfDay(hour: 9, minute: 0),
        subject: String = "Физика",
        rooms: [String] = ["А-10"]
    ) -> Lesson {
        Lesson(
            occurrenceID: "occ-\(day.storageKey)-\(bell)",
            day: day,
            bell: bell,
            start: start,
            end: TimeOfDay(hour: start.hour + 1, minute: 30),
            subject: subject,
            type: .lecture,
            teachers: ["Иванов"],
            rooms: rooms,
            groups: ["ИКБО-10-25"]
        )
    }

    @Test("Время показа — начало пары минус заданные минуты")
    func fireTime() throws {
        let day = DayKey(year: 2026, month: 10, day: 5)   // понедельник
        let now = date(day, TimeOfDay(hour: 7, minute: 0))

        let planned = NotificationPlanner.plan(
            lessons: [lesson(on: day)],
            minutesBefore: 10,
            now: now,
            calendar: calendar
        )

        let only = try #require(planned.first)
        #expect(only.fireAt == date(day, TimeOfDay(hour: 8, minute: 50)))
    }

    @Test("Прошедшие занятия не планируются")
    func skipsPastLessons() {
        let day = DayKey(year: 2026, month: 10, day: 5)
        let now = date(day, TimeOfDay(hour: 12, minute: 0))

        let planned = NotificationPlanner.plan(
            lessons: [lesson(on: day)],
            minutesBefore: 10,
            now: now,
            calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test("Горизонт ограничен неделей")
    func horizonLimit() {
        let today = DayKey(year: 2026, month: 10, day: 5)
        let now = date(today, TimeOfDay(hour: 6, minute: 0))
        let inside = lesson(on: today.adding(days: 6, calendar: calendar), bell: 1)
        let outside = lesson(on: today.adding(days: 10, calendar: calendar), bell: 2)

        let planned = NotificationPlanner.plan(
            lessons: [inside, outside],
            minutesBefore: 10,
            now: now,
            calendar: calendar
        )
        #expect(planned.count == 1)
    }

    @Test("Количество напоминаний ограничено потолком")
    func cap() {
        let today = DayKey(year: 2026, month: 10, day: 5)
        let now = date(today, TimeOfDay(hour: 0, minute: 0))
        let many = (1...7).flatMap { offset -> [Lesson] in
            let day = today.adding(days: offset, calendar: calendar)
            return (1...7).map { bell in
                lesson(on: day, bell: bell, start: TimeOfDay(hour: 8 + bell, minute: 0))
            }
        }

        let planned = NotificationPlanner.plan(
            lessons: many,
            minutesBefore: 10,
            now: now,
            calendar: calendar
        )
        #expect(planned.count == NotificationPlanner.maxNotifications)
    }

    @Test("Отключённая пара не напоминает")
    func mutedLesson() {
        let day = DayKey(year: 2026, month: 10, day: 5)
        let now = date(day, TimeOfDay(hour: 6, minute: 0))

        let planned = NotificationPlanner.plan(
            lessons: [lesson(on: day)],
            minutesBefore: 10,
            isMuted: { _ in true },
            now: now,
            calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test("Нулевой интервал означает «выключено»")
    func disabled() {
        let day = DayKey(year: 2026, month: 10, day: 5)
        let planned = NotificationPlanner.plan(
            lessons: [lesson(on: day)],
            minutesBefore: 0,
            now: date(day, TimeOfDay(hour: 6, minute: 0)),
            calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test("Идентификатор стабилен и уникален в пределах дня")
    func identifiers() {
        let day = DayKey(year: 2026, month: 10, day: 5)
        let first = NotificationPlanner.identifier(for: lesson(on: day, bell: 1))
        let second = NotificationPlanner.identifier(for: lesson(on: day, bell: 2))
        let same = NotificationPlanner.identifier(for: lesson(on: day, bell: 1))

        #expect(first == same)
        #expect(first != second)
        #expect(first == "lesson-2026-10-05-1")
    }

    /// Шаблоны задаются явно: в тестовом бандле каталога строк нет, поэтому
    /// `String(localized:)` вернул бы сам ключ вместо текста. Логика
    /// форматирования от этого не зависит — проверяем её напрямую.
    private let templates = BodyTemplates(
        room: "Через %lld мин: %@, ауд. %@",
        remote: "Через %lld мин: %@, дистанционно",
        plain: "Через %lld мин: %@"
    )

    @Test("В тексте напоминания есть аудитория")
    func bodyWithRoom() {
        let body = NotificationPlanner.body(
            for: lesson(on: DayKey(year: 2026, month: 10, day: 5), rooms: ["А-10"]),
            minutesBefore: 15,
            templates: templates
        )
        #expect(body.contains("А-10"))
        #expect(body.contains("15"))
        #expect(body.contains("Физика"))
    }

    @Test("Дистанционная пара подписана «дистанционно», а не «ауд. СДО»")
    func remoteBody() {
        let body = NotificationPlanner.body(
            for: lesson(on: DayKey(year: 2026, month: 10, day: 5), rooms: ["СДО"]),
            minutesBefore: 10,
            templates: templates
        )
        // «ауд. СДО» выглядело бы как приглашение в несуществующий кабинет.
        #expect(body.contains("дистанционно"))
        #expect(body.contains("ауд.") == false)
        #expect(body.contains("СДО") == false)
    }

    @Test("Пары без аудитории тоже напоминают")
    func bodyWithoutRoom() {
        let body = NotificationPlanner.body(
            for: lesson(on: DayKey(year: 2026, month: 10, day: 5), rooms: []),
            minutesBefore: 10,
            templates: templates
        )
        #expect(body == "Через 10 мин: Физика")
    }

    @Test("Напоминания упорядочены по дню и паре")
    func ordering() {
        let first = DayKey(year: 2026, month: 10, day: 5)
        let second = DayKey(year: 2026, month: 10, day: 6)
        let now = date(first, TimeOfDay(hour: 0, minute: 0))

        let planned = NotificationPlanner.plan(
            lessons: [
                lesson(on: second, bell: 1),
                lesson(on: first, bell: 3),
                lesson(on: first, bell: 2),
            ],
            minutesBefore: 10,
            now: now,
            calendar: calendar
        )
        #expect(planned.map(\.fireAt) == planned.map(\.fireAt).sorted())
    }
}