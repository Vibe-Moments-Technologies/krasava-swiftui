import Foundation

/// Что лежит в кэше одного расписания.
///
/// Храним правила повторения, а не развёрнутые даты: файл остаётся маленьким,
/// а окно дат можно менять без перезаписи кэша.
struct CachedSchedule: Codable, Sendable {
    /// Версия схемы кэша. Несовпадение — кэш считается несовместимым и
    /// перезагружается. Без этого поля любое изменение модели ломало бы
    /// приложение у тех, кто обновился.
    static let currentSchemaVersion = 2

    var schemaVersion: Int = CachedSchedule.currentSchemaVersion
    var target: ScheduleTarget
    var occurrences: [Occurrence]
    var weekMarkers: [WeekMarker]
    var semesterStart: DayKey?
    var semesterEnd: DayKey?
    /// Когда фид был успешно загружен — для TTL и для честной пометки
    /// «данные устарели» в виджете.
    var fetchedAt: Date

    var isCompatible: Bool { schemaVersion == Self.currentSchemaVersion }
}

/// Кэш сразу всех сохранённых расписаний.
///
/// Один файл вместо файла на расписание: их обычно одно-два, а атомарная
/// запись целого списка исключает рассинхрон между списком расписаний и их
/// данными — при раздельном хранении он неизбежен.
struct CachedSchedules: Codable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = CachedSchedules.currentSchemaVersion
    var items: [CachedSchedule] = []

    var isCompatible: Bool { schemaVersion == Self.currentSchemaVersion }

    func schedule(for targetID: Int) -> CachedSchedule? {
        items.first { $0.target.id == targetID }
    }

    mutating func upsert(_ schedule: CachedSchedule) {
        if let index = items.firstIndex(where: { $0.target.id == schedule.target.id }) {
            items[index] = schedule
        } else {
            items.append(schedule)
        }
    }

    mutating func remove(targetID: Int) {
        items.removeAll { $0.target.id == targetID }
    }
}

/// Файловое хранилище приложения.
///
/// Разделение каталогов осмысленное и влияет на бэкап:
///  * **Application Support** — заметки, переопределения, настройки. Это то,
///    что пользователь создал сам и что нельзя восстановить из сети. Попадает
///    в бэкап устройства.
///  * **Caches** — расписание. Восстанавливается одним запросом, поэтому в
///    бэкапе ему делать нечего (и Apple за это может отклонить приложение,
///    если кэш раздувает резервную копию).
struct AppFileStorage: Sendable {
    // `FileManager` не Sendable, поэтому не храним его в поле: тип объявлен
    // Sendable, и хранимое не-Sendable свойство не прошло бы проверку Swift 6.
    init() {}

    private var fileManager: FileManager { .default }

    /// Каталог с пользовательскими данными (бэкапится).
    func supportDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try ensureDirectory(base.appending(path: "KrasavaSwiftUI", directoryHint: .isDirectory))
    }

    /// Каталог кэша (не бэкапится).
    func cacheDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try ensureDirectory(base.appending(path: "KrasavaSwiftUI", directoryHint: .isDirectory))
    }

    private func ensureDirectory(_ url: URL) throws -> URL {
        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    // MARK: - Чтение и запись

    func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Атомарная запись.
    ///
    /// Обязательна: приложение может быть убито системой посреди записи, и
    /// без атомарности пользователь получил бы обрезанный JSON вместо кэша.
    func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        _ = try ensureDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }

    func remove(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}

/// Кэш расписаний в Caches.
struct ScheduleCache: Sendable {
    private let storage: AppFileStorage
    private let fileName = "schedules.json"

    init(storage: AppFileStorage) {
        self.storage = storage
    }

    private func url() throws -> URL {
        try storage.cacheDirectory().appending(path: fileName)
    }

    func load() -> CachedSchedules {
        guard let url = try? url(),
              let cached = storage.read(CachedSchedules.self, from: url),
              cached.isCompatible else {
            return CachedSchedules()
        }
        return cached
    }

    func save(_ schedules: CachedSchedules) {
        guard let url = try? url() else { return }
        var payload = schedules
        payload.schemaVersion = CachedSchedules.currentSchemaVersion
        try? storage.write(payload, to: url)
    }

    func clear() {
        guard let url = try? url() else { return }
        storage.remove(url)
    }
}