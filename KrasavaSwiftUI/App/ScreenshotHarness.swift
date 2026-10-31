import Foundation

#if DEBUG
/// Режим снятия скриншотов для CI.
///
/// Зачем: вёрстку надо видеть. `ImageRenderer` для этого не годится — он не
/// отрисовывает lazy-контейнеры, `NavigationStack` и живые эффекты, поэтому
/// вместо экрана получается пустой прямоугольник. Единственный честный способ
/// увидеть приложение — запустить его на симуляторе и снять экран через
/// `simctl io screenshot`.
///
/// Чтобы это работало без ручного тыканья, приложение принимает аргументы
/// запуска:
///   `-seedDemo`                 — заполнить стор демонстрационными данными;
///   `-screenshotScreen <имя>`   — открыть конкретный экран (schedule,
///                                 settings, about, lesson).
///
/// Всё это живёт только в DEBUG-сборке и в релиз не попадает.
enum ScreenshotHarness {

    /// Включён ли демо-режим.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemo")
    }

    /// Какой экран показать.
    static var screen: String {
        value(for: "-screenshotScreen") ?? "schedule"
    }

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif