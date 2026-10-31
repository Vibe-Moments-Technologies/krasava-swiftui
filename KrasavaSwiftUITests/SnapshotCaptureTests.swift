@testable import KrasavaSwiftUI
import SwiftUI
import UIKit
import XCTest

/// Снимки экранов для проверки вёрстки.
///
/// Зачем это здесь: UI писался без возможности посмотреть результат, и по
/// описанию задач не видно, как вёрстка выглядит на самом деле. Тест рендерит
/// ключевые экраны и прикладывает PNG к результату прогона, а CI вытаскивает
/// их из `.xcresult` — по картинкам можно судить о вёрстке, а не догадываться.
///
/// Почему XCTest, а не Swift Testing: `XCTAttachment` вместе с
/// `xcresulttool export attachments` — проверенный путь вытащить картинки с
/// симулятора. Через контейнер приложения это ненадёжно: путь зависит от того,
/// как Xcode переустановил бандл, а переменные окружения оболочки до процесса
/// тестов не доходят.
///
/// Ограничение: `ImageRenderer` не рисует живые эффекты (`glassEffect`,
/// материалы) и системные панели. Отступы, размеры, наложение и цвета он
/// показывает честно — этого хватает, чтобы ловить вёрстку; стекло по этим
/// снимкам оценивать нельзя.
@MainActor
final class SnapshotCaptureTests: XCTestCase {

    /// Размер экрана iPhone 17 (6.3").
    private let size = CGSize(width: 402, height: 874)
    private let scale: CGFloat = 2

    func testCaptureScreens() throws {
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let store = makeStore()
            let preferences = store.preferences

            capture(
                ScheduleScreen()
                    .environment(store)
                    .environment(preferences),
                named: "01-schedule-\(suffix)",
                scheme: scheme
            )

            capture(
                WeekStrip(
                    selectedDay: ScheduleStore.previewMonday(),
                    calculator: store.weekCalculator,
                    dayTypes: store.dayTypes,
                    overrides: store.overrides,
                    twoWeeks: false,
                    onSelect: { _ in }
                )
                .padding(),
                named: "02-weekstrip-\(suffix)",
                scheme: scheme,
                height: 170
            )

            capture(
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
                .background(Color(uiColor: .systemBackground)),
                named: "03-cards-\(suffix)",
                scheme: scheme,
                height: 430
            )

            capture(
                SettingsSheet()
                    .environment(store)
                    .environment(preferences),
                named: "04-settings-\(suffix)",
                scheme: scheme
            )

            capture(
                NavigationStack { AboutView() },
                named: "05-about-\(suffix)",
                scheme: scheme
            )

            capture(
                NavigationStack {
                    LessonDetailView(lesson: store.lessons(on: ScheduleStore.previewMonday()).first!)
                        .environment(store)
                },
                named: "06-lesson-\(suffix)",
                scheme: scheme
            )
        }
    }

    // MARK: - Вспомогательное

    private func makeStore() -> ScheduleStore {
        // Отдельный набор настроек: снимки не должны зависеть от прошлых прогонов.
        let defaults = UserDefaults(suiteName: "krasava.snapshots") ?? .standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pref.") {
            defaults.removeObject(forKey: key)
        }
        let store = ScheduleStore(preferences: Preferences(defaults: defaults))
        store.applyPreviewData()
        return store
    }

    private func capture(
        _ view: some View,
        named name: String,
        scheme: ColorScheme,
        height: CGFloat? = nil
    ) {
        let content = view
            .frame(width: size.width, height: height ?? size.height)
            .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(
            width: size.width,
            height: height ?? size.height
        )

        guard let image = renderer.uiImage else {
            XCTFail("Не удалось отрисовать \(name)")
            return
        }

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        // Без этого Xcode выбрасывает вложения успешных тестов, и забирать
        // из результата было бы нечего.
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}