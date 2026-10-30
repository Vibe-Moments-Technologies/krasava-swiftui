import Foundation

/// Тема оформления. По умолчанию — системная: приложение не навязывает
/// собственную палитру, а наследует системную.
enum ThemeMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "theme.system")
        case .light:  String(localized: "theme.light")
        case .dark:   String(localized: "theme.dark")
        }
    }
}

/// Пользовательские настройки отображения и уведомлений.
///
/// Намеренно плоская и маленькая: только то, что меняет вид пар или приход
/// напоминаний. Всё остальное — оформление, интеграции — решается системой.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let theme = "pref.theme"
        static let showEmptyLessons = "pref.showEmptyLessons"
        static let hideAdditional = "pref.hideAdditional"
        static let abbreviatedNames = "pref.abbreviatedNames"
        static let autoScroll = "pref.autoScroll"
        static let lessonProgress = "pref.lessonProgress"
        static let breakProgress = "pref.breakProgress"
        static let calendarTwoWeeks = "pref.calendarTwoWeeks"
        static let calendarCollapsed = "pref.calendarCollapsed"
        static let notificationsEnabled = "pref.notificationsEnabled"
        static let notifyMinutesBefore = "pref.notifyMinutesBefore"
    }

    private let defaults: UserDefaults

    var theme: ThemeMode {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }
    var showEmptyLessons: Bool {
        didSet { defaults.set(showEmptyLessons, forKey: Key.showEmptyLessons) }
    }
    var hideAdditional: Bool {
        didSet { defaults.set(hideAdditional, forKey: Key.hideAdditional) }
    }
    var abbreviatedNames: Bool {
        didSet { defaults.set(abbreviatedNames, forKey: Key.abbreviatedNames) }
    }
    var autoScrollToCurrent: Bool {
        didSet { defaults.set(autoScrollToCurrent, forKey: Key.autoScroll) }
    }
    var showLessonProgress: Bool {
        didSet { defaults.set(showLessonProgress, forKey: Key.lessonProgress) }
    }
    var showBreakProgress: Bool {
        didSet { defaults.set(showBreakProgress, forKey: Key.breakProgress) }
    }
    /// Календарь на две недели: чётная и нечётная рядом — так видно, какая
    /// неделя впереди без перелистывания.
    var calendarTwoWeeks: Bool {
        didSet { defaults.set(calendarTwoWeeks, forKey: Key.calendarTwoWeeks) }
    }
    var calendarCollapsed: Bool {
        didSet { defaults.set(calendarCollapsed, forKey: Key.calendarCollapsed) }
    }
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }
    /// За сколько минут напоминать. 0 — напоминания выключены.
    var notifyMinutesBefore: Int {
        didSet { defaults.set(notifyMinutesBefore, forKey: Key.notifyMinutesBefore) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = ThemeMode(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        self.showEmptyLessons = defaults.object(forKey: Key.showEmptyLessons) as? Bool ?? true
        self.hideAdditional = defaults.object(forKey: Key.hideAdditional) as? Bool ?? false
        self.abbreviatedNames = defaults.object(forKey: Key.abbreviatedNames) as? Bool ?? false
        self.autoScrollToCurrent = defaults.object(forKey: Key.autoScroll) as? Bool ?? true
        self.showLessonProgress = defaults.object(forKey: Key.lessonProgress) as? Bool ?? true
        self.showBreakProgress = defaults.object(forKey: Key.breakProgress) as? Bool ?? true
        self.calendarTwoWeeks = defaults.object(forKey: Key.calendarTwoWeeks) as? Bool ?? false
        self.calendarCollapsed = defaults.object(forKey: Key.calendarCollapsed) as? Bool ?? false
        self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? false
        let minutes = defaults.object(forKey: Key.notifyMinutesBefore) as? Int ?? 10
        self.notifyMinutesBefore = Self.allowedReminderMinutes.contains(minutes) ? minutes : 10
    }

    /// Допустимые значения «за сколько минут». Фиксированный список вместо
    /// свободного поля: произвольное число легко превратить в «за 1 минуту»,
    /// что бесполезно, или в «за 600», что тоже бесполезно.
    static let allowedReminderMinutes = [5, 10, 15, 20, 30, 45, 60]
}