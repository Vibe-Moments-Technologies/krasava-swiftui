import Foundation

/// Готовое к показу состояние виджета.
///
/// Логика выбора пары живёт здесь, а не во вью: во вью нет текущего времени,
/// а состояние должно соответствовать моменту записи таймлайна, а не моменту
/// отрисовки. Тот же движок используется всеми размерами виджета.
struct WidgetPresentation: Sendable {
    enum Status: Sendable, Equatable {
        /// Пара идёт прямо сейчас.
        case current
        /// До начала осталось `minutes` (включительно до 30).
        case soon(minutes: Int)
        /// Пара в будущем.
        case upcoming
    }

    var targetTitle: String?
    var primary: WidgetLesson?
    var primaryStatus: Status?
    /// Прогресс идущей пары 0…1. nil — пара не идёт.
    var progress: Double?
    /// Остальные занятия того же дня, которые ещё не начались.
    var upcomingSameDay: [WidgetLesson]
    /// Ближайшие дни с занятиями: подпись и список.
    var nextDays: [WidgetDaySummary]
    /// Данных нет вовсе — показывается пустое состояние.
    var isEmpty: Bool { primary == nil }
}

/// День занятий для виджета.
struct WidgetDaySummary: Sendable, Identifiable {
    let day: DayKey
    /// Подпись вида «ПТ, 23 ОКТ» — локаль берётся из системы.
    let label: String
    let lessons: [WidgetLesson]

    var id: String { day.storageKey }
}

/// Выбор активной пары и подготовка состояния для вью.
///
/// Повторяет правила оригинального приложения, потому что они уже проверены
/// людьми: текущая пара → ближайшая предстоящая → первая пара ближайшего
/// учебного дня. Порог «скоро» — 30 минут включительно.
enum WidgetSelection {
    /// Порог статуса «скоро».
    static let soonThresholdMinutes = 30

    static func make(
        snapshot: WidgetSnapshot,
        now: Date,
        calendar: Calendar = ScheduleClock.calendar
    ) -> WidgetPresentation {
        let ordered = snapshot.lessons.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.bell != rhs.bell { return lhs.bell < rhs.bell }
            return lhs.id < rhs.id
        }

        guard !ordered.isEmpty else {
            return WidgetPresentation(
                targetTitle: snapshot.targetTitle,
                primary: nil,
                primaryStatus: nil,
                progress: nil,
                upcomingSameDay: [],
                nextDays: []
            )
        }

        let current = ordered.first { isOngoing($0, at: now, calendar: calendar) }
        let nextUpcoming = ordered.first { lesson in
            guard let start = startDate(lesson, calendar: calendar) else { return false }
            return start > now
        }
        guard let primary = current ?? nextUpcoming else {
            // Все занятия уже прошли — показывать нечего.
            return WidgetPresentation(
                targetTitle: snapshot.targetTitle,
                primary: nil,
                primaryStatus: nil,
                progress: nil,
                upcomingSameDay: [],
                nextDays: []
            )
        }

        let primaryDay = DayKey(iso: primary.date).map { $0.mondayOfWeek(calendar: calendar) }
        _ = primaryDay

        let sameDay = ordered.filter { $0.date == primary.date }
        let upcomingSameDay = sameDay.filter { lesson in
            lesson.id != primary.id
                && (startDate(lesson, calendar: calendar) ?? .distantPast) > now
        }

        return WidgetPresentation(
            targetTitle: snapshot.targetTitle,
            primary: primary,
            primaryStatus: status(for: primary, isCurrent: current != nil, now: now, calendar: calendar),
            progress: progress(for: primary, now: now, calendar: calendar),
            upcomingSameDay: upcomingSameDay,
            nextDays: nextDays(after: primary.date, in: ordered, calendar: calendar, limit: 2)
        )
    }

    // MARK: - Примитивы

    static func isOngoing(_ lesson: WidgetLesson, at now: Date, calendar: Calendar) -> Bool {
        guard let start = startDate(lesson, calendar: calendar),
              let end = endDate(lesson, calendar: calendar) else { return false }
        // Верхняя граница строгая: в момент окончания пара уже закончилась,
        // и активной становится следующая.
        return now >= start && now < end
    }

    static func startDate(_ lesson: WidgetLesson, calendar: Calendar) -> Date? {
        date(lesson, time: lesson.start, calendar: calendar)
    }

    static func endDate(_ lesson: WidgetLesson, calendar: Calendar) -> Date? {
        date(lesson, time: lesson.end, calendar: calendar)
    }

    private static func date(_ lesson: WidgetLesson, time raw: String, calendar: Calendar) -> Date? {
        guard let day = DayKey(iso: lesson.date),
              let time = TimeOfDay(parsing: raw) else { return nil }
        return calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day,
            hour: time.hour, minute: time.minute
        ))
    }

    private static func status(
        for primary: WidgetLesson,
        isCurrent: Bool,
        now: Date,
        calendar: Calendar
    ) -> WidgetPresentation.Status {
        if isCurrent { return .current }
        guard let start = startDate(primary, calendar: calendar) else { return .upcoming }
        let minutes = Int(start.timeIntervalSince(now) / 60)
        // Порог включительный: ровно «за 30 минут» — уже «скоро».
        return (0...soonThresholdMinutes).contains(minutes) ? .soon(minutes: minutes) : .upcoming
    }

    private static func progress(for lesson: WidgetLesson, now: Date, calendar: Calendar) -> Double? {
        guard let start = startDate(lesson, calendar: calendar),
              let end = endDate(lesson, calendar: calendar),
              now >= start, now < end else { return nil }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return nil }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// Ближайшие учебные дни после указанного.
    ///
    /// Перебираем именно даты занятий, а не календарные дни: виджет должен
    /// перескочить пустые выходные и сразу показать следующий учебный день.
    private static func nextDays(
        after primaryDate: String,
        in lessons: [WidgetLesson],
        calendar: Calendar,
        limit: Int
    ) -> [WidgetDaySummary] {
        guard let primaryDay = DayKey(iso: primaryDate) else { return [] }

        var orderedDays: [DayKey] = []
        for lesson in lessons {
            guard let day = DayKey(iso: lesson.date), day > primaryDay else { continue }
            if !orderedDays.contains(day) { orderedDays.append(day) }
        }

        return orderedDays.sorted().prefix(limit).map { day in
            WidgetDaySummary(
                day: day,
                label: compactLabel(for: day, calendar: calendar),
                lessons: lessons.filter { $0.date == day.storageKey }
            )
        }
    }

    /// Подпись дня «ПТ, 23 ОКТ».
    ///
    /// Локаль — системная, а не захардкоженная `ru_RU`: приложение
    /// многоязычное, и на английском подпись должна стать «FRI, 23 OCT».
    static func compactLabel(for day: DayKey, calendar: Calendar = ScheduleClock.calendar) -> String {
        guard let date = day.date(calendar: calendar) else { return day.storageKey }
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(.current))
        let dayMonth = date.formatted(.dateTime.day().month(.abbreviated).locale(.current))
        return "\(weekday), \(dayMonth)".uppercased()
    }

    /// Заголовок дня: «СЕГОДНЯ · СРЕДА» для сегодняшнего, иначе компактная дата.
    static func headerLabel(for day: DayKey, now: Date, calendar: Calendar = ScheduleClock.calendar) -> String {
        if day == DayKey(now, calendar: calendar) {
            let weekday = day.date(calendar: calendar)?
                .formatted(.dateTime.weekday(.wide).locale(.current)) ?? ""
            let today = String(localized: "widget.today")
            return weekday.isEmpty ? today : "\(today) · \(weekday)".uppercased()
        }
        return compactLabel(for: day, calendar: calendar)
    }
}