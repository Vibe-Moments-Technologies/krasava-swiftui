import Foundation

/// Определение типа занятия по данным фида.
///
/// Логика перенесена из оригинального приложения как отлаженная: вуз присылает
/// и полное название типа («Практические занятия»), и аббревиатуру («ПР»),
/// причём филиалы используют свои аббревиатуры (ЛЕК, ЗД, ДЗ, КОНС).
///
/// Порядок проверок здесь — не стилистика, а исправление конкретных багов:
///  * полное название проверяется раньше аббревиатуры, потому что оно надёжнее;
///  * «доп» проверяется раньше «пр», иначе «доп. практика» уедет в практику.
enum LessonTypeResolver {

    /// Главная точка входа: полное название приоритетнее аббревиатуры.
    static func resolve(fullName: String?, abbreviation: String?) -> LessonType {
        if let fullName, let byFullName = resolve(fullName: fullName) {
            return byFullName
        }
        return resolve(abbreviation: abbreviation ?? "")
    }

    /// Тип по полному названию. nil — если название не распознано вообще,
    /// тогда вызывающий пробует аббревиатуру.
    static func resolve(fullName: String) -> LessonType? {
        let normalized = normalize(fullName)
        guard !normalized.isEmpty else { return nil }
        return switch normalized {
        case let value where value.hasPrefix("доп"):            .additional
        case let value where value.hasPrefix("лекц"):           .lecture
        case let value where value.hasPrefix("практическ"):     .practice
        case let value where value.hasPrefix("лабораторн"):     .lab
        case let value where value.hasPrefix("экзамен"):        .exam
        case let value where value.hasPrefix("зачет"):          .credit
        case let value where value.hasPrefix("курсовая"):       .coursework
        case let value where value.hasPrefix("курсовой"):       .coursework
        case let value where value.hasPrefix("консультац"):     .consultation
        case let value where value.hasPrefix("самостоятельн"):  .individual
        default:                                                nil
        }
    }

    /// Тип по аббревиатуре из фида.
    static func resolve(abbreviation: String) -> LessonType {
        let value = abbreviation.trimmingCharacters(in: .whitespaces).uppercased()
        guard !value.isEmpty else { return .other }

        // Порядок важен: «доп» раньше «пр», иначе «ДОП ПР» станет практикой.
        if value.contains("ДОП") { return .additional }
        if value.contains("ЛК") || value.contains("ЛЕК") { return .lecture }
        if value.contains("ЛАБ") || value.contains("ЛР") { return .lab }
        if value.contains("ПР") { return .practice }
        if value.contains("ЭКЗ") || value == "Э" { return .exam }
        if value.contains("ЗАЧ") || value == "З" || value.contains("ЗД") || value.contains("ДЗ") {
            return .credit
        }
        if value.contains("КОНС") || value.contains("КТ") { return .consultation }
        if value.contains("КР") { return .coursework }
        if value.contains("СР") { return .individual }
        return .other
    }

    /// Приведение к сравнимому виду: нижний регистр, `ё` → `е`, схлопнутые
    /// пробелы. Фид пишет «Зачёт» и «зачет» вперемешку.
    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}