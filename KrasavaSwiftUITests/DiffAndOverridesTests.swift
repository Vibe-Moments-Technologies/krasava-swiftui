import Foundation
import Testing

/// Сравнение расписания до и после обновления.
@Suite("Изменения в расписании")
struct DiffEngineTests {

    private let window = DayKey(year: 2026, month: 9, day: 1)...DayKey(year: 2026, month: 12, day: 31)

    private func lesson(
        _ subject: String,
        day: DayKey = DayKey(year: 2026, month: 9, day: 14),
        bell: Int = 1,
        rooms: [String] = ["А-10"],
        teachers: [String] = ["Иванов"],
        start: TimeOfDay = TimeOfDay(hour: 9, minute: 0)
    ) -> Lesson {
        Lesson(
            occurrenceID: "\(subject)-\(day)-\(bell)",
            day: day,
            bell: bell,
            start: start,
            end: TimeOfDay(hour: 10, minute: 30),
            subject: subject,
            type: .lecture,
            teachers: teachers,
            rooms: rooms,
            groups: ["ИКБО-10-25"]
        )
    }

    @Test("Одинаковые расписания не дают изменений")
    func noChanges() {
        let lessons = [lesson("Физика"), lesson("Математика")]
        #expect(DiffEngine.diff(old: lessons, new: lessons, from: window).isEmpty)
    }

    @Test("Новая пара считается добавленной")
    func added() {
        let changes = DiffEngine.diff(
            old: [lesson("Физика")],
            new: [lesson("Физика"), lesson("Математика")],
            from: window
        )
        #expect(changes.count == 1)
        #expect(changes.first?.kind == .added)
        #expect(changes.first?.subject == "Математика")
    }

    @Test("Пропавшая пара считается отменённой")
    func cancelled() {
        let changes = DiffEngine.diff(
            old: [lesson("Физика"), lesson("Математика")],
            new: [lesson("Физика")],
            from: window
        )
        #expect(changes.count == 1)
        #expect(changes.first?.kind == .cancelled)
        #expect(changes.first?.subject == "Математика")
    }

    @Test("Смена аудитории — это правка, а не отмена с добавлением")
    func roomChangeIsModification() {
        let changes = DiffEngine.diff(
            old: [lesson("Физика", rooms: ["А-10"])],
            new: [lesson("Физика", rooms: ["С-20"])],
            from: window
        )
        #expect(changes.count == 1)
        #expect(changes.first?.kind == .modified)
    }

    @Test("Смена преподавателя и времени тоже правка")
    func teacherAndTimeChange() {
        let changes = DiffEngine.diff(
            old: [lesson("Физика")],
            new: [lesson("Физика", teachers: ["Петров"], start: TimeOfDay(hour: 10, minute: 40))],
            from: window
        )
        #expect(changes.count == 1)
        #expect(changes.first?.kind == .modified)
        // Две правки сразу: преподаватель и время.
        #expect(changes.first?.details.count == 2)
    }

    @Test("Регистр и лишние пробелы в названии не дают ложных изменений")
    func subjectNormalization() {
        let changes = DiffEngine.diff(
            old: [lesson("Конфигурационное управление")],
            new: [lesson("конфигурационное  управление")],
            from: window
        )
        #expect(changes.isEmpty)
    }

    @Test("Изменения сортируются по дате и номеру пары")
    func sortedOutput() {
        let early = DayKey(year: 2026, month: 9, day: 7)
        let late = DayKey(year: 2026, month: 9, day: 21)
        let changes = DiffEngine.diff(
            old: [],
            new: [
                lesson("Поздняя", day: late),
                lesson("Ранняя", day: early),
            ],
            from: window
        )
        #expect(changes.map(\.subject) == ["Ранняя", "Поздняя"])
    }

    @Test("Изменения вне окна не попадают в отчёт")
    func windowRespected() {
        let changes = DiffEngine.diff(
            old: [],
            new: [lesson("Далёкая", day: DayKey(year: 2027, month: 3, day: 1))],
            from: window
        )
        #expect(changes.isEmpty)
    }
}

/// Гибридные типы занятий и пользовательские переопределения.
@Suite("Переопределения")
struct UserOverridesTests {

    private func lesson(_ subject: String = "Физика", type: LessonType = .lecture) -> Lesson {
        Lesson(
            occurrenceID: "id",
            day: DayKey(year: 2026, month: 9, day: 14),
            bell: 1,
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 10, minute: 30),
            subject: subject,
            type: type,
            teachers: [],
            rooms: [],
            groups: []
        )
    }

    @Test("Без переопределений тип берётся из фида")
    func fallbackToFeedType() {
        let overrides = UserOverrides.empty
        #expect(overrides.effectiveType(for: lesson(type: .practice)) == .practice)
    }

    @Test("Тип предмета переопределяет тип из фида")
    func subjectOverride() {
        var overrides = UserOverrides.empty
        overrides.setSubjectType(.lab, for: "Физика")
        #expect(overrides.effectiveType(for: lesson(type: .lecture)) == .lab)
    }

    @Test("Переопределение пары важнее переопределения предмета")
    func lessonOverrideWins() {
        var overrides = UserOverrides.empty
        overrides.setSubjectType(.lab, for: "Физика")
        overrides.setLessonType(.exam, for: lesson())
        #expect(overrides.effectiveType(for: lesson()) == .exam)
    }

    @Test("Переопределение снимается возвратом в nil")
    func overrideReset() {
        var overrides = UserOverrides.empty
        overrides.setSubjectType(.lab, for: "Физика")
        overrides.setSubjectType(nil, for: "Физика")
        #expect(overrides.effectiveType(for: lesson(type: .lecture)) == .lecture)
        #expect(overrides.subjectTypes.isEmpty)
    }

    @Test("Цвет типа сохраняется и сбрасывается")
    func colorOverride() {
        var overrides = UserOverrides.empty
        overrides.setColor(TypeColor(hex: 0x336699), for: .lecture)
        #expect(overrides.color(for: .lecture)?.hex == 0x336699)

        overrides.setColor(nil, for: .lecture)
        #expect(overrides.color(for: .lecture) == nil)
    }

    @Test("Цвет типа переживает кодирование в JSON")
    func colorCodable() throws {
        var overrides = UserOverrides.empty
        overrides.setColor(TypeColor(hex: 0xABCDEF), for: .lab)
        overrides.setSubjectType(.practice, for: "Физика")

        let data = try JSONEncoder().encode(overrides)
        let restored = try JSONDecoder().decode(UserOverrides.self, from: data)
        #expect(restored.color(for: .lab)?.hex == 0xABCDEF)
        #expect(restored.subjectTypes["физика"] == .practice)
    }
}

/// Видимость занятий: доп. пары и скрытые предметы.
@Suite("Видимость занятий")
struct VisibilityFilterTests {

    private func lesson(_ subject: String, type: LessonType) -> Lesson {
        Lesson(
            occurrenceID: "id-\(subject)",
            day: DayKey(year: 2026, month: 9, day: 14),
            bell: 1,
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 10, minute: 30),
            subject: subject,
            type: type,
            teachers: [],
            rooms: [],
            groups: []
        )
    }

    @Test("Доп. занятия скрываются по настройке")
    func hideAdditional() {
        let filter = VisibilityFilter(hideAdditional: true)
        let lessons = [lesson("Физика", type: .lecture), lesson("Кружок", type: .additional)]
        #expect(filter.visible(lessons, overrides: .empty).count == 1)
    }

    @Test("Скрытый предмет не виден даже если это обычная пара")
    func hideSubject() {
        let filter = VisibilityFilter(hiddenSubjects: ["физика"])
        let lessons = [lesson("Физика", type: .lecture), lesson("Математика", type: .practice)]
        let visible = filter.visible(lessons, overrides: .empty)
        #expect(visible.map(\.subject) == ["Математика"])
    }

    @Test("Скрытие учитывает переопределение типа")
    func hideAdditionalAfterOverride() {
        var overrides = UserOverrides.empty
        overrides.setSubjectType(.additional, for: "Физика")
        let filter = VisibilityFilter(hideAdditional: true)
        #expect(filter.visible([lesson("Физика", type: .lecture)], overrides: overrides).isEmpty)
    }

    @Test("Отключение напоминаний работает и по паре, и по предмету")
    func muting() {
        var overrides = UserOverrides.empty
        let physics = lesson("Физика", type: .lecture)
        let filter = VisibilityFilter()

        #expect(filter.isLessonMuted(physics, overrides: overrides) == false)

        overrides.mutedSubjects.insert(UserOverrides.subjectKey("Физика"))
        #expect(filter.isLessonMuted(physics, overrides: overrides))

        overrides.mutedSubjects.removeAll()
        overrides.mutedLessons.insert(
            UserOverrides.lessonKey(day: physics.day, bell: physics.bell, subject: physics.subject)
        )
        #expect(filter.isLessonMuted(physics, overrides: overrides))
    }
}