import Foundation

#if DEBUG
/// Данные для превью и снимков экрана.
///
/// Нужны, чтобы UI можно было отрисовать без сети, без диска и без ручного
/// тыканья: в CI тесты рендерят экраны в PNG, и по ним видно, как вёрстка
/// выглядит на самом деле.
extension ScheduleStore {

    /// Маленький, но представительный срез фида: пары разных типов, пара без
    /// аудитории, дистанционная пара и пустой день между ними.
    static let previewICal = #"""
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:X-SCHEDULE-VERSION
X-SV-START:2026-08-31T21:00:00.0000000Z
X-SV-END:2026-12-30T21:00:00.0000000Z
END:X-SCHEDULE-VERSION
BEGIN:VEVENT
DTEND;VALUE=DATE:20260908
DTSTART;VALUE=DATE:20260901
SUMMARY:1 неделя
TRANSP:TRANSPARENT
UID:w1
END:VEVENT
BEGIN:VEVENT
DTEND;VALUE=DATE:20260915
DTSTART;VALUE=DATE:20260907
SUMMARY:2 неделя
TRANSP:TRANSPARENT
UID:w2
END:VEVENT
BEGIN:VEVENT
CATEGORIES:ЛК
DTEND;TZID=Europe/Moscow:20260914T103000
DTSTART;TZID=Europe/Moscow:20260914T090000
RRULE:FREQ=WEEKLY;INTERVAL=1;UNTIL=20261230T210000Z
SUMMARY:ЛК Конфигурационное управление
TRANSP:OPAQUE
UID:p1
X-META-AUDITORIUM;VALUE=TEXT;ID=320;TYPE=3;NUMBER=А-10;CAMPUS=В-78:А-10 (В-78)
X-META-DISCIPLINE;VALUE=TEXT:Конфигурационное управление
X-META-FULL_LESSON_TYPE;VALUE=TEXT:Лекции
X-META-GROUP;VALUE=TEXT;ID=5539;TYPE=1:ИКБО-10-25
X-META-LESSON_TYPE;VALUE=TEXT:ЛК
X-META-TEACHER;VALUE=TEXT;ID=959;TYPE=2:Мирзоян Дмитрий Ильич
END:VEVENT
BEGIN:VEVENT
CATEGORIES:ПР
DTEND;TZID=Europe/Moscow:20260914T121000
DTSTART;TZID=Europe/Moscow:20260914T104000
RRULE:FREQ=WEEKLY;INTERVAL=1;UNTIL=20261230T210000Z
SUMMARY:ПР Аналитическая практика
TRANSP:OPAQUE
UID:p2
X-META-AUDITORIUM;VALUE=TEXT;ID=837;TYPE=3;NUMBER=С-20
X-META-DISCIPLINE;VALUE=TEXT:Аналитическая практика
X-META-FULL_LESSON_TYPE;VALUE=TEXT:Практические занятия
X-META-GROUP;VALUE=TEXT;ID=5539;TYPE=1:ИКБО-10-25
X-META-LESSON_TYPE;VALUE=TEXT:ПР
X-META-TEACHER;VALUE=TEXT;ID=640;TYPE=2:Алпатов Алексей Николаевич
END:VEVENT
BEGIN:VEVENT
CATEGORIES:ЛАБ
DTEND;TZID=Europe/Moscow:20260914T155000
DTSTART;TZID=Europe/Moscow:20260914T142000
RRULE:FREQ=WEEKLY;INTERVAL=1;UNTIL=20261230T210000Z
SUMMARY:ЛАБ Программирование
TRANSP:OPAQUE
UID:p3
X-META-AUDITORIUM;VALUE=TEXT;ID=12;TYPE=3;NUMBER:СДО
X-META-DISCIPLINE;VALUE=TEXT:Программирование
X-META-FULL_LESSON_TYPE;VALUE=TEXT:Лабораторные работы
X-META-GROUP;VALUE=TEXT;ID=5539;TYPE=1:ИКБО-10-25
X-META-LESSON_TYPE;VALUE=TEXT:ЛАБ
X-META-TEACHER;VALUE=TEXT;ID=1;TYPE=2:Петров Пётр Петрович
END:VEVENT
END:VCALENDAR
"""#

    /// Заполнить стор демонстрационными данными, минуя сеть и диск.
    ///
    /// Используется только превью и снимками экрана. Вызывается после создания
    /// стора: дальше он живёт обычной жизнью, но данные уже «загружены».
    func applyPreviewData(
        day: DayKey? = nil,
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
        let parsed = ICalParser.parse(Self.previewICal)

        var schedules = CachedSchedules()
        schedules.upsert(
            CachedSchedule(
                target: target,
                occurrences: parsed.occurrences,
                weekMarkers: parsed.weekMarkers,
                semesterStart: parsed.semesterStart,
                semesterEnd: parsed.semesterEnd,
                fetchedAt: Date()
            )
        )
        if let extraTarget {
            schedules.upsert(
                CachedSchedule(
                    target: extraTarget,
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
            day: day ?? Self.previewMonday()
        )

        if let note, let first = allLessons.first {
            setNote(note, forLesson: first)
        }
    }

    /// День, на который в демо-данных точно есть пары (понедельник недели
    /// с первой лекцией).
    static func previewMonday() -> DayKey {
        ICalParser.parse(previewICal).occurrences.first?.firstDay
            ?? DayKey(year: 2026, month: 9, day: 14)
    }
}
#endif