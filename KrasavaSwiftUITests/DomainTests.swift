import Foundation
import Testing

/// Даты, звонки и раскладка ленты.
@Suite("Даты и звонки")
struct CalendarBasicsTests {

    @Test("Понедельник недели и день недели")
    func mondayAndWeekday() {
        let tuesday = DayKey(year: 2026, month: 9, day: 1)
        #expect(tuesday.isoWeekday() == 2)
        #expect(tuesday.mondayOfWeek() == DayKey(year: 2026, month: 8, day: 31))

        let monday = DayKey(year: 2026, month: 9, day: 7)
        #expect(monday.isoWeekday() == 1)
        #expect(monday.mondayOfWeek() == monday)

        let sunday = DayKey(year: 2026, month: 9, day: 13)
        #expect(sunday.isoWeekday() == 7)
        #expect(sunday.mondayOfWeek() == monday)
    }

    @Test("Сдвиг через календарь переживает границу месяца")
    func addingDays() {
        let endOfSeptember = DayKey(year: 2026, month: 9, day: 28)
        #expect(endOfSeptember.adding(days: 14) == DayKey(year: 2026, month: 10, day: 12))
        #expect(endOfSeptember.adding(days: -28) == DayKey(year: 2026, month: 8, day: 31))
    }

    @Test(
        "Дата разбирается из обоих форматов фида",
        arguments: [
            "20260914T090000",             // DTSTART
            "2026-08-31T21:00:00.0000000Z" // X-SV-START
        ]
    )
    func parseFormats(input: String) {
        #expect(DayKey(iso: input) != nil)
    }

    @Test("Битые даты не превращаются в валидные")
    func rejectsGarbage() {
        #expect(DayKey(iso: "мусор") == nil)
        #expect(DayKey(iso: "20261301") == nil) // 13-й месяц
    }

    @Test("Время разбирается из iCal и из строки")
    func parseTime() {
        #expect(ICalParser.parseTime("20260914T090000") == TimeOfDay(hour: 9, minute: 0))
        #expect(ICalParser.parseTime("20260914T104000") == TimeOfDay(hour: 10, minute: 40))
        #expect(ICalParser.parseTime("20260914") == nil)
        #expect(TimeOfDay(parsing: "9:05") == TimeOfDay(hour: 9, minute: 5))
        #expect(TimeOfDay(parsing: "0905") == TimeOfDay(hour: 9, minute: 5))
        #expect(TimeOfDay(parsing: "25:00") == nil)
    }

    @Test("Номер пары привязывается к сетке звонков")
    func bellNumber() {
        #expect(Bells.bellNumber(for: TimeOfDay(hour: 9, minute: 0)) == 1)
        #expect(Bells.bellNumber(for: TimeOfDay(hour: 8, minute: 50)) == 1)
        #expect(Bells.bellNumber(for: TimeOfDay(hour: 10, minute: 40)) == 2)
        #expect(Bells.bellNumber(for: TimeOfDay(hour: 12, minute: 40)) == 3)
        #expect(Bells.bellNumber(for: TimeOfDay(hour: 18, minute: 0)) == 6)
        #expect(Bells.bellNumber(for: TimeOfDay(hour: 19, minute: 40)) == 7)
    }

    @Test("Перемена считается только вперёд")
    func breakDuration() {
        #expect(
            Bells.breakMinutes(
                from: TimeOfDay(hour: 10, minute: 30),
                to: TimeOfDay(hour: 10, minute: 40)
            ) == 10
        )
        #expect(
            Bells.breakMinutes(
                from: TimeOfDay(hour: 12, minute: 0),
                to: TimeOfDay(hour: 10, minute: 0)
            ) == 0
        )
    }
}

/// Сборка ленты дня.
@Suite("Лента дня")
struct ScheduleBuilderTests {

    private func feed() -> ICalParser.Feed {
        ICalParser.parse(Fixtures.feedSample)
    }

    private func builder(window: ScheduleBuilder.Window) -> ScheduleBuilder {
        ScheduleBuilder(occurrences: feed().occurrences, window: window)
    }

    @Test("Занятия раскладываются по дням в пределах окна")
    func lessonsByDay() {
        let window = ScheduleBuilder.Window(
            from: DayKey(year: 2026, month: 9, day: 1),
            to: DayKey(year: 2026, month: 9, day: 30)
        )
        let byDay = builder(window: window).lessonsByDay()

        let lectureDay = DayKey(year: 2026, month: 9, day: 14)
        #expect(byDay[lectureDay]?.count == 1)

        // 21 сентября занятия нет: лекция идёт через неделю, а практика —
        // только по вторникам.
        #expect(byDay[DayKey(year: 2026, month: 9, day: 21)] == nil)
    }

    @Test("Пустые пары добавляются только при включённой настройке")
    func emptySlots() {
        let day = DayKey(year: 2026, month: 9, day: 14)
        let lessons = builder(window: ScheduleBuilder.Window.around(day)).lessonsByDay()[day] ?? []

        let withEmpty = builder(window: ScheduleBuilder.Window.around(day))
            .slots(for: day, lessons: lessons, showEmpty: true)
        let withoutEmpty = builder(window: ScheduleBuilder.Window.around(day))
            .slots(for: day, lessons: lessons, showEmpty: false)

        #expect(withoutEmpty.count == 1)
        #expect(withEmpty.count == 7)
        #expect(withEmpty.first?.isActive == true)
        #expect(withEmpty.last?.isActive == false)
    }

    @Test("В воскресенье пустых пар нет")
    func sundayHasNoEmptySlots() {
        let sunday = DayKey(year: 2026, month: 9, day: 13)
        let slots = builder(window: ScheduleBuilder.Window.around(sunday))
            .slots(for: sunday, lessons: [], showEmpty: true)
        #expect(slots.isEmpty)
    }

    @Test("Две пары в один слот остаются отдельными занятиями")
    func parallelLessonsStaySeparate() {
        let day = DayKey(year: 2026, month: 9, day: 14)
        let occurrence = feed().occurrences[0]
        let first = Lesson(
            occurrenceID: "a", day: day, bell: 1,
            start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 10, minute: 30),
            subject: "Первая", type: .lecture, teachers: ["Иванов"], rooms: ["А-10"], groups: []
        )
        let second = Lesson(
            occurrenceID: "b", day: day, bell: 1,
            start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 10, minute: 30),
            subject: "Вторая", type: .practice, teachers: ["Петров"], rooms: ["А-11"], groups: []
        )
        #expect(occurrence.bell == 1)

        let slots = builder(window: ScheduleBuilder.Window.around(day))
            .slots(for: day, lessons: [first, second], showEmpty: false)
        #expect(slots.count == 1)
        #expect(slots[0].lessons.count == 2)
    }
}

/// Заметки: главный регресс — они не должны теряться при обновлении фида.
@Suite("Заметки")
struct NotesRegressionTests {

    private func lessons(from feed: ICalParser.Feed, around day: DayKey) -> [Lesson] {
        ScheduleBuilder(
            occurrences: feed.occurrences,
            window: ScheduleBuilder.Window.around(day)
        ).lessonsByDay().values.flatMap { $0 }
    }

    @Test("Ключ заметки не зависит от UID события")
    func keySurvivesUIDRotation() throws {
        let day = DayKey(year: 2026, month: 9, day: 14)
        let original = try #require(
            lessons(from: ICalParser.parse(Fixtures.feedSample), around: day)
                .first { $0.subject == "Конфигурационное управление" }
        )
        let rotated = try #require(
            lessons(from: ICalParser.parse(Fixtures.feedSampleWithRotatedUIDs), around: day)
                .first { $0.subject == "Конфигурационное управление" }
        )

        // UID действительно поменялся — иначе тест ничего не проверял бы.
        #expect(original.occurrenceID != rotated.occurrenceID)

        let originalKey = NoteKeys.lesson(targetID: 5539, day: original.day, bell: original.bell)
        let rotatedKey = NoteKeys.lesson(targetID: 5539, day: rotated.day, bell: rotated.bell)
        #expect(originalKey == rotatedKey)
    }

    @Test("Ключ переживает смену регистра и лишние пробелы в названии")
    func keyNormalizesSubject() {
        let first = NoteKeys.subject(targetID: 5539, subject: "Конфигурационное  управление")
        let second = NoteKeys.subject(targetID: 5539, subject: "конфигурационное управление ")
        #expect(first == second)
    }

    @Test("Заметки разных расписаний не пересекаются")
    func keysAreScopedByTarget() {
        let day = DayKey(year: 2026, month: 9, day: 14)
        #expect(
            NoteKeys.lesson(targetID: 5539, day: day, bell: 1)
            != NoteKeys.lesson(targetID: 5541, day: day, bell: 1)
        )
    }

    @Test("Заметки к разным парам одного дня различаются")
    func lessonKeysDifferByBell() {
        let day = DayKey(year: 2026, month: 9, day: 14)
        #expect(
            NoteKeys.lesson(targetID: 5539, day: day, bell: 1)
            != NoteKeys.lesson(targetID: 5539, day: day, bell: 2)
        )
    }
}