import Foundation

/// Ошибки обращения к серверу расписания.
enum ScheduleAPIError: LocalizedError, Sendable {
    case offline
    case httpStatus(Int)
    case malformedResponse
    case emptySchedule

    var errorDescription: String? {
        switch self {
        case .offline:
            String(localized: "error.offline")
        case .httpStatus(let code):
            String(format: String(localized: "error.http"), code)
        case .malformedResponse:
            String(localized: "error.malformed")
        case .emptySchedule:
            String(localized: "error.emptySchedule")
        }
    }
}

/// Клиент публичного API расписания РТУ МИРЭА.
///
/// Ровно два GET-запроса, оба только на чтение. Никакой аналитики,
/// идентификаторов устройства и сторонних SDK — это осознанное свойство
/// приложения, а не временное упрощение.
struct ScheduleAPI: Sendable {
    private static let baseURL = URL(string: "https://schedule-of.mirea.ru")!
    /// Сервер отдаёт данные в зависимости от User-Agent в том числе; значение
    /// повторяет формат, к которому источник привык.
    private static let userAgent = "krasava-swiftui/0.1 (schedule fetcher)"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Поиск групп, преподавателей и аудиторий.
    func search(match: String, limit: Int = 50) async throws -> [ScheduleTarget] {
        let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пустой запрос сервер тоже обслуживает, но отдаёт нерелевантные
        // аудитории вроде «3 (ФФ)». Искать есть смысл с двух символов.
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(
            url: Self.baseURL.appending(path: "/schedule/api/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "match", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else { throw ScheduleAPIError.malformedResponse }

        let data = try await get(url)
        struct Response: Decodable { let data: [ScheduleTarget] }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ScheduleAPIError.malformedResponse
        }
        return decoded.data
    }

    /// iCal-фид выбранного расписания.
    func iCal(for target: ScheduleTarget) async throws -> String {
        var components = URLComponents(
            url: Self.baseURL.appending(
                path: "/schedule/api/ical/\(target.kind.pathName)/\(target.id)"
            ),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "includeMeta", value: "true")]
        guard let url = components?.url else { throw ScheduleAPIError.malformedResponse }

        let data = try await get(url)
        // Фид отдаёт UTF-8; если сервер вдруг ответит без заголовка кодировки,
        // пробуем windows-1251 — так вуз отдавал HTML в техобслуживание.
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1251)
        guard let text else { throw ScheduleAPIError.malformedResponse }
        return text
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/calendar", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        // Условных запросов сервер не поддерживает (не отдаёт ETag/Last-Modified),
        // поэтому кэш целиком наш — см. ScheduleCache.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ScheduleAPIError.offline
        } catch let error as URLError where error.code == .timedOut {
            throw ScheduleAPIError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw ScheduleAPIError.malformedResponse
        }
        // Сервер в техобслуживании отвечает HTML-заглушкой с 5xx. Без этой
        // проверки JSON-декодер молча вернул бы пустой список, и приложение
        // затёрло бы рабочий кэш пустотой.
        guard (200..<300).contains(http.statusCode) else {
            throw ScheduleAPIError.httpStatus(http.statusCode)
        }
        return data
    }
}