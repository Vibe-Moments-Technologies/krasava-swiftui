@testable import KrasavaSwiftUI
import Foundation
import Testing

/// Разбор реального фида.
///
/// Эти тесты — регресс на конкретные места, где ломались прошлые реализации:
/// переносы строк, маркеры недель, `RRULE` через неделю, `EXDATE` и «СДО».
@Suite("Разбор iCal")
struct ICalParserTests {

    private func parsed() -> ICalParser.Feed {
        ICalParser.parse(Fixtures.feedSample)
    }

    @Test("Маркеры недель разбираются и выравниваются на понедельник")
    func weekMarkers() {
        let feed = parsed()
        #expect(feed.weekMarkers.count == 3)
        #expect(feed.weekMarkers.map(\.number) == [1, 2, 3])
        // «1 неделя» начинается 1 сентября 2026 — это вторник, поэтому маркер
        // обязан съехать на понедельник 31 августа.
        #expect(feed.weekMarkers[0].monday == DayKey(year: 2026, month: 8, day: 31))
        #expect(feed.weekMarkers[1].monday == DayKey(year: 2026, month: 9, day: 7))
    }

    @Test("Служебные события не попадают в занятия")
    func markersAreNotLessons() {
        let feed = parsed()
        #expect(feed.occurrences.count == 3)
        #expect(feed.occurrences.contains { $0.subject.contains("неделя") } == false)
    }

    @Test("Перенесённые строки склеиваются")
    func unfoldedValues() throws {
        let lecture = try #require(parsed().occurrences.first { $0.type == .lecture })
        #expect(lecture.subject == "Конфигурационное управление")
        #expect(lecture.teachers == ["Мирзоян Дмитрий Ильич"])
        #expect(lecture.rooms == ["А-10 (В-78)"])
        #expect(lecture.groups == ["ИКБО-10-25"])
    }

    @Test("Номер пары считается по времени начала")
    func bellNumbers() throws {
        let feed = parsed()
        let lecture = try #require(feed.occurrences.first { $0.type == .lecture })
        #expect(lecture.bell == 1)
        #expect(lecture.start == TimeOfDay(hour: 9, minute: 0))
        #expect(lecture.end == TimeOfDay(hour: 10, minute: 30))

        let practice = try #require(feed.occurrences.first { $0.type == .practice })
        #expect(practice.bell == 2)
    }

    @Test("RRULE через неделю раскрывается с учётом EXDATE")
    func biweeklyExpansion() throws {
        let lecture = try #require(parsed().occurrences.first { $0.type == .lecture })
        #expect(lecture.intervalWeeks == 2)
        #expect(lecture.excludedDays.contains(DayKey(year: 2026, month: 12, day: 21)))

        let days = lecture.days(upTo: DayKey(year: 2026, month: 12, day: 31))
        #expect(days.count == 7)
        #expect(days.first == DayKey(year: 2026, month: 9, day: 14))
        #expect(days.contains(DayKey(year: 2026, month: 12, day: 21)) == false)
    }

    @Test("Событие без RRULE даёт ровно один день")
    func singleOccurrence() throws {
        let remote = try #require(parsed().occurrences.first { $0.type == .individual })
        let days = remote.days(upTo: DayKey(year: 2027, month: 6, day: 1))
        #expect(days == [DayKey(year: 2026, month: 9, day: 16)])
    }

    @Test("Аудитория «СДО» распознаётся как дистанционная пара")
    func remoteLesson() throws {
        let feed = parsed()
        let remote = try #require(feed.occurrences.first { $0.rooms.contains("СДО") })
        #expect(remote.type == .individual)

        let lesson = Lesson(
            occurrenceID: remote.id,
            day: DayKey(year: 2026, month: 9, day: 16),
            bell: remote.bell,
            start: remote.start,
            end: remote.end,
            subject: remote.subject,
            type: remote.type,
            teachers: remote.teachers,
            rooms: remote.rooms,
            groups: remote.groups
        )
        #expect(lesson.isRemote)
        #expect(lesson.physicalRooms.isEmpty)
    }

    @Test("Полное название типа приоритетнее аббревиатуры")
    func fullTypeWins() throws {
        let practice = try #require(parsed().occurrences.first { $0.subject.contains("Аналитическая") })
        #expect(practice.type == .practice)
    }

    @Test("Семестр берётся из служебного блока")
    func semesterRange() {
        let feed = parsed()
        #expect(feed.semesterStart == DayKey(year: 2026, month: 8, day: 31))
        #expect(feed.semesterEnd == DayKey(year: 2026, month: 12, day: 30))
    }

    @Test("HTML-заглушка вместо фида не даёт занятий")
    func garbageFeed() {
        let feed = ICalParser.parse(Fixtures.htmlInsteadOfICal)
        #expect(feed.hasLessonEvents == false)
        #expect(feed.weekMarkers.isEmpty)
    }
}

/// Номер недели, чётность и фолбэк-расчёт.
@Suite("Недели семестра")
struct WeekCalculatorTests {

    private func calculator() -> WeekCalculator {
        WeekCalculator(markers: ICalParser.parse(Fixtures.feedSample).weekMarkers)
    }

    @Test("Номер недели берётся из маркеров фида")
    func numberFromMarkers() {
        let weeks = calculator()
        #expect(weeks.weekNumber(for: DayKey(year: 2026, month: 9, day: 1)) == 1)
        #expect(weeks.weekNumber(for: DayKey(year: 2026, month: 9, day: 14)) == 3)
        #expect(weeks.weekNumber(for: DayKey(year: 2026, month: 9, day: 20)) == 3)
    }

    @Test("Чётность считается по номеру недели")
    func parity() {
        let weeks = calculator()
        #expect(weeks.isEvenWeek(DayKey(year: 2026, month: 9, day: 7)) == true)
        #expect(weeks.isEvenWeek(DayKey(year: 2026, month: 9, day: 14)) == false)
    }

    @Test("Без маркеров номер считается от начала семестра")
    func fallbackCalculation() {
        let weeks = WeekCalculator(markers: [])
        // 1 сентября 2026 — вторник; неделя считается от понедельника 31 августа,
        // иначе неполная первая неделя сдвинула бы весь семестр.
        #expect(weeks.weekNumber(for: DayKey(year: 2026, month: 9, day: 1)) == 1)
        #expect(weeks.weekNumber(for: DayKey(year: 2026, month: 9, day: 7)) == 2)
        #expect(weeks.weekNumber(for: DayKey(year: 2026, month: 2, day: 9)) == 1)
    }
}

/// Определение типа занятия.
@Suite("Типы занятий")
struct LessonTypeResolverTests {

    @Test(
        "Полное название распознаётся",
        arguments: [
            ("Лекции", LessonType.lecture),
            ("Практические занятия", .practice),
            ("Лабораторные работы", .lab),
            ("Экзамен", .exam),
            ("Зачёт", .credit),
            ("Курсовая работа", .coursework),
            ("Консультация", .consultation),
            ("Самостоятельная работа", .individual),
            ("Дополнительное занятие", .additional),
        ]
    )
    func fullNames(input: String, expected: LessonType) {
        #expect(LessonTypeResolver.resolve(fullName: input) == expected)
    }

    @Test(
        "Аббревиатуры распознаются",
        arguments: [
            ("ЛК", LessonType.lecture),
            ("ПР", .practice),
            ("ЛАБ", .lab),
            ("ЛР", .lab),
            ("ЭКЗ", .exam),
            ("ЗАЧ", .credit),
            ("КОНС", .consultation),
            ("СР", .individual),
            ("ДОП", .additional),
        ]
    )
    func abbreviations(input: String, expected: LessonType) {
        #expect(LessonTypeResolver.resolve(abbreviation: input) == expected)
    }

    @Test("«Доп» проверяется раньше «пр»")
    func additionalBeatsPractice() {
        // Иначе «ДОП ПР» уехало бы в практику — это был реальный баг.
        #expect(LessonTypeResolver.resolve(abbreviation: "ДОП ПР") == .additional)
    }

    @Test("Полное название важнее аббревиатуры")
    func fullNamePriority() {
        let resolved = LessonTypeResolver.resolve(fullName: "Лекции", abbreviation: "ПР")
        #expect(resolved == .lecture)
    }

    @Test("Неизвестное значение не роняет разбор")
    func unknownType() {
        #expect(LessonTypeResolver.resolve(fullName: "Нечто", abbreviation: nil) == .other)
        #expect(LessonTypeResolver.resolve(abbreviation: "") == .other)
    }
}