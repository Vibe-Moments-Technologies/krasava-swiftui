import Foundation

/// Одно запланированное напоминание.
struct PlannedNotification: Hashable, Sendable {
    /// Стабильный идентификатор: `lesson-<дата>-<пара>`. Повторное
    /// планирование с тем же id заменяет прошлое напоминание, а не плодит дубли.
    let id: String
    let fireAt: Date
    let title: String
    let body: String
}

/// Расчёт напоминаний о занятиях.
///
/// Чистая функция: время, календарь и список занятий приходят параметрами,
/// поэтому всё поведение проверяется тестами без `UserNotifications` и без
/// системных часов. Планировщик в приложении только превращает результат
/// в `UNNotificationRequest`.
enum NotificationPlanner {
    /// Горизонт планирования. Неделя с запасом: телефон, пролежавший запертым
    /// несколько дней, всё равно получит напоминания.
    static let horizonDays = 7

    /// Потолок на iOS — 64 ожидающих запроса на приложение. Держим 20:
    /// этого хватает на неделю занятий, и остаётся место для будущих
    /// напоминаний другого рода.
    static let maxNotifications = 20

    /// Запланировать напоминания на `horizonDays` вперёд.
    ///
    /// - Parameters:
    ///   - lessons: занятия выбранного расписания (уже без скрытых предметов).
    ///   - minutesBefore: за сколько минут напоминать; 0 и меньше — выключено.
    ///   - isMuted: отключено ли напоминание для конкретной пары или предмета.
    ///   - now: текущий момент; прошедшие моменты не планируются.
    static func plan(
        lessons: [Lesson],
        minutesBefore: Int,
        isMuted: (Lesson) -> Bool = { _ in false },
        now: Date = Date(),
        calendar: Calendar = ScheduleClock.calendar
    ) -> [PlannedNotification] {
        guard minutesBefore > 0 else { return [] }

        let today = DayKey(now, calendar: calendar)
        let horizon = today.adding(days: horizonDays, calendar: calendar)

        let candidates = lessons
            .filter { $0.day >= today && $0.day <= horizon }
            .filter { !isMuted($0) }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day { return lhs.day < rhs.day }
                return lhs.bell < rhs.bell
            }

        var planned: [PlannedNotification] = []
        for lesson in candidates {
            guard planned.count < maxNotifications else { break }
            guard let fireAt = fireDate(for: lesson, minutesBefore: minutesBefore, calendar: calendar),
                  fireAt > now else { continue }

            planned.append(
                PlannedNotification(
                    id: identifier(for: lesson),
                    fireAt: fireAt,
                    title: String(localized: "notification.title"),
                    body: body(for: lesson, minutesBefore: minutesBefore)
                )
            )
        }
        return planned
    }

    /// Время показа: начало пары минус `minutesBefore`.
    ///
    /// Считается через календарь, а не вычитанием секунд из даты: переход на
    /// летнее время сдвинул бы показ на час, а пара осталась бы в 09:00.
    static func fireDate(
        for lesson: Lesson,
        minutesBefore: Int,
        calendar: Calendar = ScheduleClock.calendar
    ) -> Date? {
        calendar.date(
            from: DateComponents(
                year: lesson.day.year,
                month: lesson.day.month,
                day: lesson.day.day,
                hour: lesson.start.hour,
                minute: lesson.start.minute
            )
        )?.addingTimeInterval(-Double(minutesBefore) * 60)
    }

    static func identifier(for lesson: Lesson) -> String {
        "lesson-\(lesson.day.storageKey)-\(lesson.bell)"
    }

    /// Текст напоминания.
    ///
    /// «СДО» — это сайт вуза, а не аудитория, поэтому для дистанционной пары
    /// пишем «дистанционно», а не «ауд. СДО»: иначе напоминание выглядит как
    /// приглашение в несуществующий кабинет.
    static func body(for lesson: Lesson, minutesBefore: Int) -> String {
        if lesson.isRemote {
            return String(
                format: String(localized: "notification.body.remote"),
                minutesBefore,
                lesson.subject
            )
        }
        if let room = lesson.physicalRooms.first {
            return String(
                format: String(localized: "notification.body.room"),
                minutesBefore,
                lesson.subject,
                room
            )
        }
        return String(
            format: String(localized: "notification.body.plain"),
            minutesBefore,
            lesson.subject
        )
    }
}