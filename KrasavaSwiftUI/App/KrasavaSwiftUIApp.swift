import SwiftUI

/// Точка входа приложения.
@main
struct KrasavaSwiftUIApp: App {
    @State private var preferences: Preferences
    @State private var store: ScheduleStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let preferences = Preferences()
        let store = ScheduleStore(preferences: preferences)
        // Напоминания планируются снаружи `Shared`: пакет общий с виджетом,
        // а расширению работать с UserNotifications незачем.
        store.onScheduleChanged = {
            Task { await Self.rescheduleNotifications(for: store) }
        }
        #if DEBUG
        // CI снимает экраны на симуляторе: без этих данных показывать нечего,
        // а сеть в таком прогоне недоступна.
        if ScreenshotHarness.isEnabled {
            store.applyPreviewData()
        }
        #endif
        _preferences = State(initialValue: preferences)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(preferences)
                // Тема по умолчанию — системная: `nil` означает «как в системе»,
                // и приложение наследует оформление, ничего не навязывая.
                .preferredColorScheme(preferences.theme.colorScheme)
                .task {
                    // Статус разрешения перечитывается до первой загрузки:
                    // если пользователь запретил уведомления в системных
                    // настройках, тумблер должен оказаться выключенным.
                    await LessonNotifications.shared.refreshAuthorizationStatus()
                    await store.bootstrap()
                    await Self.rescheduleNotifications(for: store)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                // Возврат в foreground — единственный момент, когда тихое
                // обновление уместно: в фоне приложение не должно будить радио.
                await LessonNotifications.shared.refreshAuthorizationStatus()
                if store.hasSchedule, store.isCacheStale {
                    await store.refresh(silent: true)
                }
                await Self.rescheduleNotifications(for: store)
            }
        }
    }

    /// Пересчёт напоминаний по текущему состоянию.
    ///
    /// Одна точка входа: смена расписания, настроек, типов и скрытых предметов
    /// проходит через неё, поэтому «скрытый предмет» исчезает и из напоминаний.
    @MainActor
    private static func rescheduleNotifications(for store: ScheduleStore) async {
        let minutes = store.preferences.notificationsEnabled
            ? store.preferences.notifyMinutesBefore
            : 0
        let filter = VisibilityFilter(hiddenSubjects: store.overrides.hiddenSubjects)
        await LessonNotifications.shared.reschedule(
            lessons: store.allLessons,
            minutesBefore: minutes,
            isMuted: { filter.isLessonMuted($0, overrides: store.overrides) }
        )
    }
}

extension ThemeMode {
    /// `nil` — следовать системе.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}