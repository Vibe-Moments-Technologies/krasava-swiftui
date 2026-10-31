import Foundation
import Observation

/// Центральное состояние приложения.
///
/// Единственное место, где меняются данные расписания. Экраны читают отсюда
/// и вызывают методы — никаких собственных копий состояния и никаких сетевых
/// вызовов из вью.
///
/// Производительность: развёрнутые занятия считаются **один раз** при смене
/// данных и складываются в `allLessons`/`lessonsByDay`. Раньше они считались
/// на каждое обращение, и лента из сотни страниц разворачивала правила
/// повторения на каждый кадр — отсюда были лаги на кнопках.
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

    // MARK: - Состояние

    private(set) var savedTargets: [ScheduleTarget] = []
    private(set) var selectedTargetID: Int?

    private var cached = CachedSchedules()
    /// Правила повторения выбранного расписания.
    private var occurrences: [Occurrence] = []

    // Развёрнутые данные выбранного расписания — пересчитываются при изменениях.
    private(set) var allLessons: [Lesson] = []
    private(set) var lessonsByDay: [DayKey: [Lesson]] = [:]
    private(set) var dayTypes: [DayKey: [LessonType]] = [:]
    private(set) var weekCalculator = WeekCalculator(markers: [])

    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Изменения, найденные при последнем обновлении.
    private(set) var pendingChanges: [ScheduleChange] = []
    /// Дата, которую сейчас показывает лента.
    var selectedDay: DayKey

    // MARK: - Пользовательские данные

    var overrides: UserOverrides {
        didSet {
            overridesStore.save(overrides)
            rebuildDerived()
            publishDownstream()
        }
    }
    private(set) var notes: [LessonNote]

    /// Хук «данные изменились».
    ///
    /// Приложение подключает сюда перепланирование напоминаний. Сделано
    /// замыканием, а не прямой зависимостью: `Shared` компилируется и в
    /// виджет, который не имеет права работать с `UserNotifications`.
    var onScheduleChanged: (@MainActor () -> Void)?

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
        self.savedTargets = selection.targets
        self.selectedTargetID = selection.selectedID ?? selection.targets.first?.id
        self.cached = cache.load()
        self.overrides = overridesStore.load()
        self.notes = notesStore.load()
        self.selectedDay = ScheduleClock.today()

        loadSelectedOccurrences()
        rebuildDerived()
    }

    // MARK: - Производные данные

    var selectedTarget: ScheduleTarget? {
        guard let selectedTargetID else { return nil }
        return savedTargets.first { $0.id == selectedTargetID }
    }

    var hasSchedule: Bool { selectedTarget != nil }

    /// Окно дат, в котором считается расписание.
    var window: ScheduleBuilder.Window {
        ScheduleBuilder.Window.around(ScheduleClock.today())
    }

    func lessons(on day: DayKey) -> [Lesson] {
        lessonsByDay[day] ?? []
    }

    /// Слоты дня. Строятся из уже развёрнутых занятий — без пересчёта правил.
    func slots(on day: DayKey) -> [DaySlot] {
        ScheduleBuilder(occurrences: [], window: window)
            .slots(for: day, lessons: lessons(on: day), showEmpty: preferences.showEmptyLessons)
    }

    var selectedFetchedAt: Date? {
        guard let selectedTargetID else { return nil }
        return cached.schedule(for: selectedTargetID)?.fetchedAt
    }

    /// Кэш выбранного расписания считается устаревшим после TTL.
    var isCacheStale: Bool {
        guard let fetchedAt = selectedFetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) >= Self.cacheTTL
    }

    // MARK: - Жизненный цикл

    /// Загрузка при старте: сначала кэш (мгновенно), потом тихое обновление.
    func bootstrap() async {
        guard hasSchedule else { return }
        if isCacheStale {
            await refresh(silent: true)
        }
    }

    /// Перезагрузка выбранного расписания из сети.
    func refresh(silent: Bool = false) async {
        guard let target = selectedTarget else { return }
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
            cached.upsert(schedule)
            cache.save(cached)

            occurrences = schedule.occurrences
            rebuildDerived()
            errorMessage = nil
            persistSelection()

            // Изменения считаем только если раньше было с чем сравнивать.
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

    /// Добавить расписание в список и открыть его.
    func addTarget(_ target: ScheduleTarget) async {
        if !savedTargets.contains(where: { $0.id == target.id }) {
            savedTargets.append(target)
        }
        selectedTargetID = target.id
        pendingChanges = []
        selectedDay = ScheduleClock.today()
        loadSelectedOccurrences()
        persistSelection()
        rebuildDerived()
        await refresh(silent: false)
    }

    /// Переключиться на сохранённое расписание.
    func select(targetID: Int) {
        guard selectedTargetID != targetID else { return }
        selectedTargetID = targetID
        pendingChanges = []
        selectedDay = ScheduleClock.today()
        loadSelectedOccurrences()
        persistSelection()
        rebuildDerived()
        publishDownstream()

        // Данные могли устареть, пока расписание было неактивным.
        if isCacheStale {
            Task { await refresh(silent: true) }
        }
    }

    /// Убрать расписание из списка вместе с его кэшем и заметками.
    ///
    /// Заметки удаляются только здесь и только по явному действию пользователя.
    /// В оригинале каскад срабатывал на обновлении — это и стирало заметки.
    func removeTarget(id: Int) {
        savedTargets.removeAll { $0.id == id }
        cached.remove(targetID: id)
        cache.save(cached)
        notes.removeAll { $0.key.contains(":\(id):") }
        notesStore.save(notes)

        if selectedTargetID == id {
            selectedTargetID = savedTargets.first?.id
            selectedDay = ScheduleClock.today()
            loadSelectedOccurrences()
        }
        persistSelection()
        rebuildDerived()
        publishDownstream()
    }

    /// Настройки отображения изменились — производные данные надо пересобрать.
    ///
    /// Вызывается из UI после правки `Preferences`: стор не наблюдает за
    /// настройками напрямую, поэтому изменение приходит явным сигналом.
    func preferencesDidChange() {
        rebuildDerived()
        publishDownstream()
    }

    // MARK: - Заметки

    func note(for key: String) -> LessonNote? {
        notes.first { $0.key == key }
    }

    func text(forLesson lesson: Lesson) -> String {
        guard let selectedTargetID else { return "" }
        let key = NoteKeys.lesson(targetID: selectedTargetID, day: lesson.day, bell: lesson.bell)
        return note(for: key)?.text ?? ""
    }

    func text(forSubject subject: String) -> String {
        guard let selectedTargetID else { return "" }
        return note(for: NoteKeys.subject(targetID: selectedTargetID, subject: subject))?.text ?? ""
    }

    func setNote(_ text: String, forLesson lesson: Lesson) {
        guard let selectedTargetID else { return }
        upsertNote(
            key: NoteKeys.lesson(targetID: selectedTargetID, day: lesson.day, bell: lesson.bell),
            text: text
        )
    }

    func setNote(_ text: String, forSubject subject: String) {
        guard let selectedTargetID else { return }
        upsertNote(key: NoteKeys.subject(targetID: selectedTargetID, subject: subject), text: text)
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

    private func loadSelectedOccurrences() {
        guard let selectedTargetID, let schedule = cached.schedule(for: selectedTargetID) else {
            occurrences = []
            return
        }
        occurrences = schedule.occurrences
    }

    /// Пересборка развёрнутых данных. Вызывается только при реальных изменениях.
    private func rebuildDerived() {
        guard let selectedTargetID, let schedule = cached.schedule(for: selectedTargetID) else {
            allLessons = []
            lessonsByDay = [:]
            dayTypes = [:]
            weekCalculator = WeekCalculator(markers: [])
            return
        }

        weekCalculator = WeekCalculator(markers: schedule.weekMarkers)

        let filter = VisibilityFilter(
            hideAdditional: preferences.hideAdditional,
            hiddenSubjects: overrides.hiddenSubjects
        )
        let byDay = ScheduleBuilder(occurrences: schedule.occurrences, window: window)
            .lessonsByDay()
            .mapValues { filter.visible($0, overrides: overrides) }

        lessonsByDay = byDay
        allLessons = byDay.values.flatMap { $0 }
        dayTypes = byDay.mapValues { lessons in
            lessons
                .sorted { $0.bell < $1.bell }
                .map { overrides.effectiveType(for: $0) }
        }
    }

    private func persistSelection() {
        var selection = SelectionStore.Selection()
        selection.targets = savedTargets
        selection.selectedID = selectedTargetID
        selection.lastSync = Dictionary(
            uniqueKeysWithValues: cached.items.map { (String($0.target.id), $0.fetchedAt) }
        )
        selectionStore.save(selection)
    }

    /// Публикация данных наружу: снимок для виджета и перепланирование
    /// напоминаний. Оба шага должны видеть одно и то же состояние.
    private func publishDownstream() {
        WidgetSnapshotWriter.write(
            WidgetSnapshotWriter.makeSnapshot(
                targetTitle: selectedTarget?.displayTitle,
                lessons: allLessons,
                overrides: overrides,
                today: ScheduleClock.today()
            )
        )
        onScheduleChanged?()
    }

    #if DEBUG
    /// Заполнить стор данными напрямую, минуя сеть и диск.
    ///
    /// Нужно превью и снимкам экрана в CI: без этого UI не отрисовать, потому
    /// что данные приходят только из сети.
    func seed(
        targets: [ScheduleTarget],
        selectedID: Int?,
        schedules: CachedSchedules,
        overrides newOverrides: UserOverrides,
        day: DayKey
    ) {
        savedTargets = targets
        selectedTargetID = selectedID
        cached = schedules
        selectedDay = day
        loadSelectedOccurrences()
        // `overrides` — свойство с наблюдателем: присваивание само пересоберёт
        // производные данные. Порядок важен, поэтому кэш выставлен выше.
        overrides = newOverrides
        rebuildDerived()
    }
    #endif
}