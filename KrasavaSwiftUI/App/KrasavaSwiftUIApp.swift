import SwiftUI

/// Точка входа приложения.
@main
struct KrasavaSwiftUIApp: App {
    @State private var preferences: Preferences
    @State private var store: ScheduleStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let preferences = Preferences()
        _preferences = State(initialValue: preferences)
        _store = State(initialValue: ScheduleStore(preferences: preferences))
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
                    await store.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Возврат в foreground — единственный момент, когда тихое
            // обновление уместно: в фоне приложение не должно будить радио.
            guard phase == .active, store.hasSchedule, store.isCacheStale else { return }
            Task { await store.refresh(silent: true) }
        }
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