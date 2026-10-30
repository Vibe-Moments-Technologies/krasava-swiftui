import Foundation
import Observation

/// Центральное состояние приложения.
///
/// Единственное место, где меняются данные расписания. Экраны читают отсюда
/// и вызывают методы — никаких собственных копий состояния и никаких сетевых
/// вызовов из вью.
@MainActor
@Observable
final class ScheduleStore {

    /// Как часто считаем кэш свежим. Те же 30 минут, что в оригинале:
    /// расписание меняется редко, а лишние запросы расходуют батарею.
    static let cacheTTL: TimeInterval = 30 * 60

    // MARK: - Зависимости

    private let api: ScheduleAPI
    private let cache: ScheduleCache
    private let notesStore: NotesStore
    private let overridesStore: OverridesStore
    private let selectionStore: SelectionStore
    let preferences: Preferences

    // MARK: - Состояние расписания

    private(set) var target: ScheduleTarget?
    private(set) var occurrences: [Occurrence] = []
    private(set) var weekMarkers: [WeekMarker] = []
    private(set) var semesterStart: DayKey?
    private(set) var semesterEnd: DayKey?
    private(set) var fetchedAt: Date?

    // MARK: - Состояние интерфейса

    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Изменения, найденные при последнем обновлении. Пусто — показывать нечего.
    private(set) var pendingChanges: [ScheduleChange] = []
    /// Дата, которую сейчас показывает лента.
    var selectedDay: DayKey

    // MARK: - Пользовательские данные

    var overrides: UserOverrides {
        didSet { overridesStore.save(overrides); publishDownstream() }
    }
    private(set) var notes: [LessonNote]

    init(
        api: ScheduleAPI = ScheduleAPI(),
        preferences: Preferences,
        storage: AppFileStorage = AppFileStorage()
    ) {
        self.api = api
        self.preferences = preferences
        self.cache = ScheduleCache(storage: storage)
        self.notesStore = NotesStore(storage: storage)
        self.overridesStore = OverridesStore(storage: storage)
        self.selectionStore = SelectionStore(storage: storage)

        let selection = selectionStore.load()
        self.target = selection.target
        self.fetchedAt = selection.lastSyncAt
        self.overrides = overridesStore.load()
        self.notes = notesStore.load()
        self.selectedDay = ScheduleClock.today()
    }

    // MARK: - Производные данные

    /// Окно дат, в котором считается расписание.
    var window: ScheduleBuilder.Window {
        ScheduleBuilder.Window.around(ScheduleClock.today())
    }

    private var builder: ScheduleBuilder {
        ScheduleBuilder(occurrences: occurrences, window: window)
    }

    /// Все занятия в окне, без учёта видимости.
    var allLessons: [Lesson] {
        builder.lessonsByDay().values.flatMap { $0 }
    }

    /// Занятия по дням с учётом скрытых предметов и доп. занятий.
    var lessonsByDay: [DayKey: [Lesson]] {
        let filter = VisibilityFilter(
            hideAdditional: preferences.hideAdditional,
            hiddenSubjects: overrides.hiddenSubjects
        )
        return builder.lessonsByDay().mapValues { filter.visible($0, overrides: overrides) }
    }

    var weekCalculator: WeekCalculator {
        WeekCalculator(markers: weekMarkers)
    }

    /// Точки-индикаторы в мини-календаре: типы занятий по дням.
    var dayTypeSummary: [DayKey: [LessonType]] {
        lessonsByDay.mapValues { lessons in
            // По одной точке на пару; при двух занятиях в одном слоте — обе.
            lessons
                .sorted { $0.bell < $1.bell }
                .map { overrides.effectiveType(for: $0) }
        }
    }

    func lessons(on day: DayKey) -> [Lesson] {
        lessonsByDay[day] ?? []
    }

    func slots(on day: DayKey) -> [DaySlot] {
        builder.slots(
            for: day,
            lessons: lessons(on: day),
            showEmpty: preferences.showEmptyLessons
        )
    }

    var hasSchedule: Bool { target != nil }

    /// Кэш считается устаревшим после TTL.
    var isCacheStale: Bool {
        guard let fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) >= Self.cacheTTL
    }

    // MARK: - Жизненный цикл

    /// Загрузка при старте: сначала кэш (мгновенно), потом тихое обновление.
    ///
    /// Порядок важен: приложение никогда не показывает пустой экран, если в
    /// кэше уже что-то есть. Сеть — второстепенный источник.
    func bootstrap() async {
        restoreFromCache()
        guard target != nil else { return }
        if isCacheStale {
            await refresh(silent: true)
        }
    }

    private func restoreFromCache() {
        guard let cached = cache.load(), cached.target.id == target?.id else { return }
        apply(cached)
    }

    /// Перезагрузка расписания из сети.
    ///
    /// `silent` — фоновое обновление: без индикатора и без экрана ошибки,
    /// потому что на экране уже есть данные.
    func refresh(silent: Bool = false) async {
        guard let target else { return }
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }

        do {
            let raw = try await api.iCal(for: target)
            let feed = ICalParser.parse(raw)

            // Защита от затирания: пустой или нераспознанный ответ не должен
            // стирать рабочее расписание. Сервер периодически отдаёт заглушку
            // на техобслуживании.
            guard feed.hasLessonEvents else {
                throw ScheduleAPIError.emptySchedule
            }

            let old = allLessons
            let schedule = CachedSchedule(
                target: target,
                occurrences: feed.occurrences,
                weekMarkers: feed.weekMarkers,
                semesterStart: feed.semesterStart,
                semesterEnd: feed.semesterEnd,
                fetchedAt: Date()
            )
            cache.save(schedule)
            apply(schedule)
            errorMessage = nil
            persistSelection()

            // Изменения считаем только если раньше было с чем сравнивать:
            // при первой загрузке «добавлено всё» — это не новость.
            if !old.isEmpty {
                pendingChanges = DiffEngine.diff(
                    old: old,
                    new: allLessons,
                    from: window.from...window.to
                )
            }

            publishDownstream()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            // С кэшем ошибку показываем мягко: данные на экране остаются.
            errorMessage = allLessons.isEmpty ? message : nil
        }
    }

    /// Выбор расписания и первичная загрузка.
    func select(_ newTarget: ScheduleTarget) async {
        if target?.id != newTarget.id {
            target = newTarget
            occurrences = []
            weekMarkers = []
            semesterStart = nil
            semesterEnd = nil
            fetchedAt = nil
            pendingChanges = []
            selectedDay = ScheduleClock.today()
        }
        persistSelection()
        await refresh(silent: false)
    }

    /// Убрать сохранённое расписание вместе с его данными.
    ///
    /// Заметки удаляются только здесь и только по явному действию пользователя.
    /// В оригинале каскад срабатывал на обновлении — это и стирало заметки.
    func removeSchedule() {
        cache.clear()
        WidgetSnapshotWriter.clear()
        target = nil
        occurrences = []
        weekMarkers = []
        fetchedAt = nil
        pendingChanges = []
        notes = []
        notesStore.save(notes)
        persistSelection()
    }

    // MARK: - Заметки

    func note(for key: String) -> LessonNote? {
        notes.first { $0.key == key }
    }

    func text(forLesson lesson: Lesson) -> String {
        guard let target else { return "" }
        let key = NoteKeys.lesson(targetID: target.id, day: lesson.day, bell: lesson.bell)
        return note(for: key)?.text ?? ""
    }

    func text(forSubject subject: String) -> String {
        guard let target else { return "" }
        let key = NoteKeys.subject(targetID: target.id, subject: subject)
        return note(for: key)?.text ?? ""
    }

    /// Сохранение заметки. Пустой текст удаляет запись, чтобы не копить пустые.
    func setNote(_ text: String, forLesson lesson: Lesson) {
        guard let target else { return }
        let key = NoteKeys.lesson(targetID: target.id, day: lesson.day, bell: lesson.bell)
        upsertNote(key: key, text: text)
    }

    func setNote(_ text: String, forSubject subject: String) {
        guard let target else { return }
        let key = NoteKeys.subject(targetID: target.id, subject: subject)
        upsertNote(key: key, text: text)
    }

    private func upsertNote(key: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.removeAll { $0.key == key }
        } else if let index = notes.firstIndex(where: { $0.key == key }) {
            notes[index].text = trimmed
            notes[index].updatedAt = Date()
        } else {
            notes.append(LessonNote(key: key, text: trimmed, updatedAt: Date()))
        }
        notesStore.save(notes)
    }

    // MARK: - Служебное

    func dismissChanges() {
        pendingChanges = []
    }

    private func apply(_ schedule: CachedSchedule) {
        occurrences = schedule.occurrences
        weekMarkers = schedule.weekMarkers
        semesterStart = schedule.semesterStart
        semesterEnd = schedule.semesterEnd
        fetchedAt = schedule.fetchedAt
    }

    private func persistSelection() {
        selectionStore.save(
            SelectionStore.Selection(target: target, lastSyncAt: fetchedAt)
        )
    }

    /// Публикация данных наружу: снимок для виджета и перепланирование
    /// напоминаний. Оба шага должны видеть одно и то же состояние, поэтому
    /// вызываются только отсюда.
    private func publishDownstream() {
        WidgetSnapshotWriter.write(
            WidgetSnapshotWriter.makeSnapshot(
                targetTitle: target?.displayTitle,
                lessons: allLessons,
                overrides: overrides,
                today: ScheduleClock.today()
            )
        )
    }
}