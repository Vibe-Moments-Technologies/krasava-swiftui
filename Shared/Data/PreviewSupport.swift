import Foundation

#if DEBUG
/// Данные для превью и скриншотов.
///
/// Нужны, чтобы UI можно было снять на симуляторе без сети: в CI приложение
/// запускается с `-seedDemo` и показывает расписание сразу.
///
/// Даты считаются **от сегодняшнего дня**, а не зашиты в сентябрь: окно
/// расписания — это ±дни вокруг сегодня, и фиксированные даты в него не
/// попадали, из-за чего демо-экран оказывался пустым.
extension ScheduleStore {

    /// Заполнить стор демонстрационными данными, минуя сеть и диск.
    func applyPreviewData(
        target: ScheduleTarget = ScheduleTarget(
            id: 5539,
            title: "ИКБО-10-25",
            fullTitle: "ИКБО-10-25",
            kind: .group
        ),
        extraTarget: ScheduleTarget? = nil,
        overrides previewOverrides: UserOverrides = .empty,
        note: String? = "взять распечатку"
    ) {
        let today = ScheduleClock.today()
        let parsed = ICalParser.parse(Self.previewICal(today: today))

        var schedules = CachedSchedules()
        for kind in [target, extraTarget].compactMap({ $0 }) {
            schedules.upsert(
                CachedSchedule(
                    target: kind,
                    occurrences: parsed.occurrences,
                    weekMarkers: parsed.weekMarkers,
                    semesterStart: parsed.semesterStart,
                    semesterEnd: parsed.semesterEnd,
                    fetchedAt: Date()
                )
            )
        }

        seed(
            targets: [target] + (extraTarget.map { [$0] } ?? []),
            selectedID: target.id,
            schedules: schedules,
            overrides: previewOverrides,
            day: today
        )

        if let note, let first = allLessons.first {
            setNote(note, forLesson: first)
        }
    }

    /// Фид с занятиями на сегодня, завтра и послезавтра.
    ///
    /// Пары намеренно разные: лекция, практика, лабораторная с «СДО» и
    /// экзамен — так на снимке видно, как выглядят все варианты карточек.
    static func previewICal(today: DayKey) -> String {
        let tomorrow = today.adding(days: 1)
        let dayAfter = today.adding(days: 2)
        let monday = today.mondayOfWeek()

        var events: [String] = [
            weekEvent(number: 3, monday: monday),
            weekEvent(number: 4, monday: monday.adding(days: 7)),
            lessonEvent(
                uid: "p1", day: today, start: "090000", end: "103000",
                subject: "Конфигурационное управление", type: "ЛК",
                fullType: "Лекции", room: "А-10 (В-78)", campus: "В-78",
                teacher: "Мирзоян Дмитрий Ильич"
            ),
            lessonEvent(
                uid: "p2", day: today, start: "104000", end: "121000",
                subject: "Аналитическая практика", type: "ПР",
                fullType: "Практические занятия", room: "С-20", campus: "С-20",
                teacher: "Алпатов Алексей Николаевич"
            ),
            lessonEvent(
                uid: "p3", day: today, start: "142000", end: "155000",
                subject: "Программирование", type: "ЛАБ",
                fullType: "Лабораторные работы", room: "СДО", campus: "СДО",
                teacher: "Петров Пётр Петрович"
            ),
            lessonEvent(
                uid: "p4", day: today, start: "162000", end: "175000",
                subject: "Физика", type: "ЛК",
                fullType: "Лекции", room: "Б-205 (В-78)", campus: "В-78",
                teacher: "Сидорова Анна Викторовна"
            ),
            lessonEvent(
                uid: "p5", day: tomorrow, start: "090000", end: "103000",
                subject: "Математический анализ", type: "ПР",
                fullType: "Практические занятия", room: "А-11 (В-78)", campus: "В-78",
                teacher: "Кузнецов Игорь Олегович"
            ),
            lessonEvent(
                uid: "p6", day: tomorrow, start: "104000", end: "121000",
                subject: "Иностранный язык", type: "ПР",
                fullType: "Практические занятия", room: "С-15 (С-20)", campus: "С-20",
                teacher: "Смирнова Ольга Ивановна"
            ),
            lessonEvent(
                uid: "p7", day: dayAfter, start: "124000", end: "141000",
                subject: "Теория вероятностей", type: "ЛК",
                fullType: "Лекции", room: "А-10 (В-78)", campus: "В-78",
                teacher: "Морозов Дмитрий Сергеевич"
            ),
            lessonEvent(
                uid: "p8", day: dayAfter, start: "142000", end: "155000",
                subject: "Физическая культура", type: "ДР",
                fullType: "Самостоятельная работа", room: "Спортзал", campus: "В-78",
                teacher: ""
            ),
        ]

        events.append("END:VCALENDAR")

        return (["BEGIN:VCALENDAR", "VERSION:2.0"] + events).joined(separator: "\n")
    }

    // MARK: - Сборка событий

    private static func icalDate(_ day: DayKey) -> String {
        String(format: "%04d%02d%02d", day.year, day.month, day.day)
    }

    private static func weekEvent(number: Int, monday: DayKey) -> String {
        """
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:\(icalDate(monday))
        DTEND;VALUE=DATE:\(icalDate(monday.adding(days: 7)))
        SUMMARY:\(number) неделя
        TRANSP:TRANSPARENT
        UID:week-\(number)
        END:VEVENT
        """
    }

    private static func lessonEvent(
        uid: String,
        day: DayKey,
        start: String,
        end: String,
        subject: String,
        type: String,
        fullType: String,
        room: String,
        campus: String,
        teacher: String
    ) -> String {
        var lines = [
            "BEGIN:VEVENT",
            "DTSTART;TZID=Europe/Moscow:\(icalDate(day))T\(start)",
            "DTEND;TZID=Europe/Moscow:\(icalDate(day))T\(end)",
            "SUMMARY:\(type) \(subject)",
            "TRANSP:OPAQUE",
            "UID:\(uid)",
            "X-META-DISCIPLINE;VALUE=TEXT:\(subject)",
            "X-META-FULL_LESSON_TYPE;VALUE=TEXT:\(fullType)",
            "X-META-LESSON_TYPE;VALUE=TEXT:\(type)",
            "X-META-AUDITORIUM;VALUE=TEXT;ID=1;TYPE=3;NUMBER=\(room);CAMPUS=\(campus):\(room)",
            "X-META-GROUP;VALUE=TEXT;ID=5539;TYPE=1:ИКБО-10-25",
        ]
        if !teacher.isEmpty {
            lines.append("X-META-TEACHER;VALUE=TEXT;ID=1;TYPE=2:\(teacher)")
        }
        lines.append("END:VEVENT")
        return lines.joined(separator: "\n")
    }
}
#endif