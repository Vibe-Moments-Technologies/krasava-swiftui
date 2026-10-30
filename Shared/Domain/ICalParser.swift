import Foundation

/// Разбор iCal-фида РТУ МИРЭА.
///
/// Формат — обычный RFC 5545 с расширениями вуза: метаданные занятий лежат в
/// свойствах `X-META-*`, а нумерация недель приходит отдельными прозрачными
/// событиями «N неделя».
///
/// Парсер намеренно не тянет стороннюю библиотеку: нужен маленький предсказуемый
/// разбор двух видов событий, а не полная поддержка календарного стандарта.
enum ICalParser {

    /// Результат разбора фида.
    struct Feed: Sendable {
        var occurrences: [Occurrence] = []
        var weekMarkers: [WeekMarker] = []
        /// Начало семестра из блока `X-SCHEDULE-VERSION` (если сервер его дал).
        var semesterStart: DayKey?
        var semesterEnd: DayKey?
        /// Были ли в фиде события занятий. Нужен, чтобы отличить «пустое
        /// расписание» от «сервер отдал заглушку».
        var hasLessonEvents: Bool { !occurrences.isEmpty }
    }

    private static let weekSummaryPrefix = "недел"
    private static let maxIntervalWeeks = 8
    /// Горизонт для правил без UNTIL. Оригинал брал 5 месяцев; здесь столько же,
    /// чтобы поведение не разошлось с привычным, но с жёстким потолком.
    private static let fallbackHorizonDays = 150

    static func parse(_ raw: String) -> Feed {
        var feed = Feed()
        var currentProps: [String: [String]] = [:]
        var blockName: String?

        for line in unfoldedLines(raw) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if let begin = blockName(of: trimmed, prefix: "BEGIN:") {
                blockName = begin
                currentProps.removeAll(keepingCapacity: true)
                continue
            }
            if let end = blockName(of: trimmed, prefix: "END:") {
                switch end {
                case "VEVENT":
                    appendEvent(props: currentProps, into: &feed)
                case "X-SCHEDULE-VERSION":
                    feed.semesterStart = day(fromProperty: "X-SV-START", in: currentProps)
                    feed.semesterEnd = day(fromProperty: "X-SV-END", in: currentProps)
                default:
                    break
                }
                blockName = nil
                currentProps.removeAll(keepingCapacity: true)
                continue
            }
            guard blockName != nil, let property = parseProperty(trimmed) else { continue }
            currentProps[property.name, default: []].append(property.value)
        }

        feed.weekMarkers = feed.weekMarkers.sorted { $0.monday < $1.monday }
        feed.occurrences.sort { lhs, rhs in
            if lhs.firstDay != rhs.firstDay { return lhs.firstDay < rhs.firstDay }
            if lhs.bell != rhs.bell { return lhs.bell < rhs.bell }
            return lhs.subject < rhs.subject
        }
        return feed
    }

    // MARK: - События

    private static func appendEvent(props: [String: [String]], into feed: inout Feed) {
        let transparency = props["TRANSP"]?.first?.uppercased() ?? ""
        let summary = props["SUMMARY"]?.first ?? ""

        // Прозрачные события — служебные: маркеры недель и прочие пометки.
        if transparency == "TRANSPARENT" {
            if let marker = weekMarker(summary: summary, props: props) {
                feed.weekMarkers.append(marker)
            }
            return
        }

        guard let occurrence = occurrence(props: props, summary: summary) else { return }
        feed.occurrences.append(occurrence)
    }

    private static func weekMarker(summary: String, props: [String: [String]]) -> WeekMarker? {
        guard summary.lowercased().contains(weekSummaryPrefix),
              let day = day(fromProperty: "DTSTART", in: props) else { return nil }
        // «1 неделя», «12 неделя» — берём ведущее число.
        let numberText = summary.prefix { $0.isNumber }
        guard let number = Int(numberText), number > 0 else { return nil }
        // Фид может начать неделю не с понедельника («1 неделя» осени 2026 —
        // вторник 1 сентября). Приводим к понедельнику здесь, чтобы все
        // потребители видели одинаковую сетку.
        return WeekMarker(number: number, monday: day.mondayOfWeek())
    }

    private static func occurrence(props: [String: [String]], summary: String) -> Occurrence? {
        guard let firstDay = day(fromProperty: "DTSTART", in: props) else { return nil }

        guard let subject = props["X-META-DISCIPLINE"]?.first?.nonEmpty
            ?? subjectFromSummary(summary) else { return nil }

        let type = LessonTypeResolver.resolve(
            fullName: props["X-META-FULL_LESSON_TYPE"]?.first,
            abbreviation: props["X-META-LESSON_TYPE"]?.first
        )

        let start = time(fromProperty: "DTSTART", in: props)
            ?? Bells.bell(number: Bells.bellNumber(for: TimeOfDay(hour: 9, minute: 0)))?.start
            ?? TimeOfDay(hour: 9, minute: 0)
        let bell = Bells.bellNumber(for: start)
        let end = time(fromProperty: "DTEND", in: props)
            ?? Bells.bell(number: bell)?.end
            ?? TimeOfDay(hour: 10, minute: 30)

        let rule = parseRule(props["RRULE"]?.first, firstDay: firstDay)

        let excluded: Set<DayKey> = Set(
            (props["EXDATE"] ?? [])
                .flatMap { $0.split(separator: ",") }
                .compactMap { DayKey(iso: String($0)) }
        )

        return Occurrence(
            id: props["UID"]?.first ?? "\(subject)@\(firstDay)@\(bell)",
            subject: subject,
            type: type,
            teachers: clean(props["X-META-TEACHER"]),
            rooms: clean(props["X-META-AUDITORIUM"] ?? props["LOCATION"]),
            groups: clean(props["X-META-GROUP"]),
            bell: bell,
            start: start,
            end: end,
            firstDay: firstDay,
            intervalWeeks: rule.intervalWeeks,
            until: rule.until,
            excludedDays: excluded
        )
    }

    /// Правило повторения. `RRULE` нет — занятие одиночное.
    private static func parseRule(_ raw: String?, firstDay: DayKey) -> (intervalWeeks: Int, until: DayKey?) {
        guard let raw, !raw.isEmpty else {
            return (1, firstDay)
        }
        var interval = 1
        var until: DayKey?
        var seenFrequency = false

        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].uppercased()
            let value = String(pair[1])
            switch key {
            case "FREQ":
                seenFrequency = true
            case "INTERVAL":
                if let parsed = Int(value), parsed > 0 {
                    interval = min(parsed, maxIntervalWeeks)
                }
            case "UNTIL":
                until = DayKey(iso: value)
            default:
                continue
            }
        }

        // Недельное правило без UNTIL не должно быть бесконечным в памяти:
        // разворачивать его будет `Occurrence.days(upTo:)`, а окно задаёт UI.
        if !seenFrequency {
            interval = 1
        }
        return (interval, until)
    }

    /// Запасной путь для фидов без `X-META-DISCIPLINE`: «ЛК Конфигурационное
    /// управление» → «Конфигурационное управление».
    private static func subjectFromSummary(_ summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].count <= 5 else { return trimmed }
        let head = String(parts[0])
        guard head.allSatisfy({ !$0.isLowercase }) else { return trimmed }
        return String(parts[1]).trimmingCharacters(in: .whitespaces).nonEmpty ?? trimmed
    }

    // MARK: - Разбор строк

    /// Строки iCal переносятся с ведущим пробелом или табом; перенос —
    /// продолжение предыдущей строки, а не новая запись.
    static func unfoldedLines(_ raw: String) -> [String] {
        var result: [String] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix(" ") || text.hasPrefix("\t") {
                if result.isEmpty {
                    result.append(String(text.dropFirst()))
                } else {
                    result[result.count - 1] += String(text.dropFirst())
                }
            } else {
                result.append(text)
            }
        }
        return result
    }

    struct Property {
        let name: String
        let params: [String: String]
        let value: String
    }

    /// `ИМЯ;ПАРАМ=ЗНАЧЕНИЕ;...:значение`.
    ///
    /// Разделитель — ПЕРВОЕ двоеточие: параметры не могут содержать двоеточие,
    /// а значение может (например `CAMPUS=В-78` идёт до него, а `А-10 (В-78)`
    /// после).
    static func parseProperty(_ line: String) -> Property? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        var segments = head.split(separator: ";", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return nil }
        let name = String(segments.removeFirst()).uppercased()
        guard !name.isEmpty else { return nil }

        var params: [String: String] = [:]
        for segment in segments {
            let pair = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 {
                params[String(pair[0]).uppercased()] = String(pair[1])
            }
        }
        return Property(name: name, params: params, value: value)
    }

    private static func blockName(of line: String, prefix: String) -> String? {
        guard line.uppercased().hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).uppercased()
    }

    private static func day(fromProperty name: String, in props: [String: [String]]) -> DayKey? {
        guard let raw = props[name]?.first else { return nil }
        return DayKey(iso: raw)
    }

    private static func time(fromProperty name: String, in props: [String: [String]]) -> TimeOfDay? {
        guard let raw = props[name]?.first else { return nil }
        return parseTime(raw)
    }

    /// Время из `20260914T090000`. nil для событий «весь день» без `T`.
    static func parseTime(_ raw: String) -> TimeOfDay? {
        guard let marker = raw.firstIndex(of: "T") else { return nil }
        let digits = Array(raw[raw.index(after: marker)...].prefix(6))
        guard digits.count >= 4,
              let hour = Int(String(digits[0..<2])),
              let minute = Int(String(digits[2..<4])),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
    }

    /// Значения `X-META-*` приходят с пробелами и пустыми строками.
    private static func clean(_ values: [String]?) -> [String] {
        (values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}