import Foundation

/// Заметки к парам и предметам.
///
/// Лежат **отдельным файлом** от кэша расписания. Это принципиально: главная
/// причина потери заметок в оригинале — каскадное удаление и перезапись
/// связанных данных при обновлении фида. Отдельный файл физически не может
/// пострадать от обновления расписания.
struct NotesStore: Sendable {
    private let storage: AppFileStorage
    private let fileName = "notes.json"

    init(storage: AppFileStorage) {
        self.storage = storage
    }

    private func url() throws -> URL {
        try storage.supportDirectory().appending(path: fileName)
    }

    func load() -> [LessonNote] {
        guard let url = try? url() else { return [] }
        return storage.read([LessonNote].self, from: url) ?? []
    }

    func save(_ notes: [LessonNote]) {
        guard let url = try? url() else { return }
        try? storage.write(notes, to: url)
    }
}

/// Пользовательские переопределения типов, цветов и скрытых предметов.
struct OverridesStore: Sendable {
    private let storage: AppFileStorage
    private let fileName = "overrides.json"

    init(storage: AppFileStorage) {
        self.storage = storage
    }

    private func url() throws -> URL {
        try storage.supportDirectory().appending(path: fileName)
    }

    func load() -> UserOverrides {
        guard let url = try? url() else { return .empty }
        return storage.read(UserOverrides.self, from: url) ?? .empty
    }

    func save(_ overrides: UserOverrides) {
        guard let url = try? url() else { return }
        try? storage.write(overrides, to: url)
    }
}

/// Выбранное расписание и служебные метки синхронизации.
///
/// Живёт в Application Support, а не в UserDefaults: это данные, которые
/// пользователь не хочет потерять при переустановке, и они должны попасть
/// в бэкап вместе с заметками.
/// Сохранённые расписания и выбранное.
///
/// Живёт в Application Support, а не в UserDefaults: пользователь добавлял эти
/// расписания руками, и они должны попасть в бэкап вместе с заметками.
/// Список и выбранный хранятся вместе — иначе после падения между двумя
/// записями выбранным мог оказаться id, которого больше нет в списке.
struct SelectionStore: Sendable {
    private let storage: AppFileStorage
    private let fileName = "selection.json"

    struct Selection: Codable, Sendable {
        var targets: [ScheduleTarget] = []
        var selectedID: Int?
        /// Моменты последней успешной загрузки по каждому расписанию — для TTL.
        var lastSync: [String: Date] = [:]

        func selectedTarget() -> ScheduleTarget? {
            targets.first { $0.id == selectedID }
        }
    }

    init(storage: AppFileStorage) {
        self.storage = storage
    }

    private func url() throws -> URL {
        try storage.supportDirectory().appending(path: fileName)
    }

    func load() -> Selection {
        guard let url = try? url() else { return Selection() }
        return storage.read(Selection.self, from: url) ?? Selection()
    }

    func save(_ selection: Selection) {
        guard let url = try? url() else { return }
        try? storage.write(selection, to: url)
    }
}