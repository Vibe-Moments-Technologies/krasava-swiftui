import Foundation

/// Что лежит в кэше расписания.
///
/// Храним правила повторения, а не развёрнутые даты: файл остаётся маленьким,
/// а окно дат можно менять без перезаписи кэша.
struct CachedSchedule: Codable, Sendable {
    /// Версия схемы кэша. Несовпадение — кэш считается несовместимым и
    /// перезагружается. Без этого поля любое изменение модели ломало бы
    /// приложение у тех, кто обновился.
    static let currentSchemaVersion = 1

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
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

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
        try ensureDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }

    func remove(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}

/// Кэш расписания в Caches.
struct ScheduleCache: Sendable {
    private let storage: AppFileStorage
    private let fileName = "schedule.json"

    init(storage: AppFileStorage) {
        self.storage = storage
    }

    private func url() throws -> URL {
        try storage.cacheDirectory().appending(path: fileName)
    }

    func load() -> CachedSchedule? {
        guard let url = try? url(),
              let cached = storage.read(CachedSchedule.self, from: url),
              cached.isCompatible else { return nil }
        return cached
    }

    func save(_ schedule: CachedSchedule) {
        guard let url = try? url() else { return }
        try? storage.write(schedule, to: url)
    }

    func clear() {
        guard let url = try? url() else { return }
        storage.remove(url)
    }
}