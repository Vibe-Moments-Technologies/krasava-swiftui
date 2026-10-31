import Foundation
import SwiftUI
import Testing
import UIKit

/// Снимки экранов.
///
/// Зачем это здесь: UI писался без возможности посмотреть результат, и по
/// описанию задач не видно, как вёрстка выглядит на самом деле. Тест рендерит
/// ключевые экраны в PNG, CI складывает их в артефакт — по картинкам можно
/// судить о вёрстке, а не догадываться.
///
/// Ограничение: `ImageRenderer` не рисует живые эффекты (`glassEffect`,
/// материалы) и не показывает системные панели. Отступы, размеры, наложение
/// и цвета он показывает честно — этого достаточно, чтобы ловить вёрстку,
/// но стекло по этим снимкам оценивать нельзя.
@MainActor
@Suite("Снимки экрана")
struct SnapshotTests {

    private var outputDirectory: URL {
        if let raw = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appending(path: "KrasavaSnapshots", directoryHint: .isDirectory)
    }

    /// Устройство, под которое считаем размеры (iPhone 17, 6.3").
    private let size = CGSize(width: 402, height: 874)
    private let scale: CGFloat = 2

    @Test("Экраны рендерятся в PNG")
    func renderScreens() throws {
        let directory = outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"

            let store = makeStore()
            let preferences = store.preferences

            try render(
                ScheduleScreen()
                    .environment(store)
                    .environment(preferences),
                named: "schedule-\(suffix)",
                scheme: scheme,
                into: directory
            )

            try render(
                SettingsSheet()
                    .environment(store)
                    .environment(preferences),
                named: "settings-\(suffix)",
                scheme: scheme,
                into: directory
            )

            try render(
                NavigationStack { AboutView() }
                    .environment(store)
                    .environment(preferences),
                named: "about-\(suffix)",
                scheme: scheme,
                into: directory
            )

            try render(
                WeekStrip(
                    selectedDay: ScheduleStore.previewMonday(),
                    calculator: store.weekCalculator,
                    dayTypes: store.dayTypes,
                    overrides: store.overrides,
                    twoWeeks: false,
                    onSelect: { _ in }
                )
                .padding()
                .environment(store)
                .environment(preferences),
                named: "weekstrip-\(suffix)",
                scheme: scheme,
                into: directory,
                height: 160
            )

            try render(
                VStack(spacing: 8) {
                    ForEach(store.lessons(on: ScheduleStore.previewMonday())) { lesson in
                        LessonCard(
                            lesson: lesson,
                            type: store.overrides.effectiveType(for: lesson),
                            notePreview: store.text(forLesson: lesson),
                            isToday: true
                        )
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                .environment(store)
                .environment(preferences),
                named: "cards-\(suffix)",
                scheme: scheme,
                into: directory,
                height: 420
            )
        }
    }

    // MARK: - Вспомогательное

    private func makeStore() -> ScheduleStore {
        // Отдельный набор настроек, чтобы снимки не зависели от прошлых прогонов.
        let defaults = UserDefaults(suiteName: "krasava.snapshots") ?? .standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pref.") {
            defaults.removeObject(forKey: key)
        }
        let store = ScheduleStore(preferences: Preferences(defaults: defaults))
        store.applyPreviewData()
        return store
    }

    private func render(
        _ view: some View,
        named name: String,
        scheme: ColorScheme,
        into directory: URL,
        height: CGFloat? = nil
    ) throws {
        let content = view
            .frame(width: size.width, height: height ?? size.height)
            .environment(\.colorScheme, scheme)
            .tint(.accentColor)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(
            width: size.width,
            height: height ?? size.height
        )

        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            Issue.record("Не удалось отрисовать \(name)")
            return
        }
        try data.write(to: directory.appending(path: "\(name).png"))
    }
}