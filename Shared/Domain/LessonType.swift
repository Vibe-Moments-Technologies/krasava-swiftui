import Foundation

/// Тип учебного занятия.
///
/// `rawValue` — стабильный ASCII-ключ. Он попадает в снапшот для виджета, в
/// пользовательские переопределения цветов и в файл настроек, поэтому менять
/// его нельзя: смена сломала бы сохранённые данные у пользователей. Человеко-
/// читаемая подпись живёт отдельно (`badge`, `displayName`) и локализуется.
enum LessonType: String, Codable, CaseIterable, Sendable {
    case lecture
    case practice
    case lab
    case exam
    case credit
    case coursework
    case consultation
    case individual
    case other
    case additional

    /// Короткий бейдж для карточки и виджета. Локализуется через каталог строк.
    var badge: String {
        switch self {
        case .lecture:      String(localized: "type.lecture.badge")
        case .practice:     String(localized: "type.practice.badge")
        case .lab:          String(localized: "type.lab.badge")
        case .exam:         String(localized: "type.exam.badge")
        case .credit:       String(localized: "type.credit.badge")
        case .coursework:   String(localized: "type.coursework.badge")
        case .consultation: String(localized: "type.consultation.badge")
        case .individual:   String(localized: "type.individual.badge")
        case .other:        String(localized: "type.other.badge")
        case .additional:   String(localized: "type.additional.badge")
        }
    }

    /// Полное название типа для экрана деталей и настроек.
    var displayName: String {
        switch self {
        case .lecture:      String(localized: "type.lecture.name")
        case .practice:     String(localized: "type.practice.name")
        case .lab:          String(localized: "type.lab.name")
        case .exam:         String(localized: "type.exam.name")
        case .credit:       String(localized: "type.credit.name")
        case .coursework:   String(localized: "type.coursework.name")
        case .consultation: String(localized: "type.consultation.name")
        case .individual:   String(localized: "type.individual.name")
        case .other:        String(localized: "type.other.name")
        case .additional:   String(localized: "type.additional.name")
        }
    }

    /// Порядок в списке «Типы и цвета» — от частых к редким.
    static var settingsOrder: [LessonType] {
        [.lecture, .practice, .lab, .exam, .credit, .coursework,
         .consultation, .individual, .other, .additional]
    }
}