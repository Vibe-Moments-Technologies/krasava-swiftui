import Foundation
import UserNotifications

/// Планировщик локальных напоминаний.
///
/// Тонкая обёртка над `UNUserNotificationCenter`: вся логика выбора пар и
/// времени живёт в `NotificationPlanner`, поэтому здесь только перевод
/// готового плана в системные запросы и работа с разрешением.
@MainActor
final class LessonNotifications {

    static let shared = LessonNotifications()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Напоминания разрешены системой прямо сейчас.
    ///
    /// Синхронного ответа у системы нет, поэтому статус кэшируется при
    /// обновлении. Тумблер в настройках обязан показывать правду: если
    /// пользователь запретил уведомления в системных настройках, тумблер
    /// не должен оставаться включённым.
    private(set) var isAuthorized = false

    /// Запросить разрешение (вызывается при включении тумблера, не на старте).
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        return granted
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Перепланировать напоминания под текущее состояние расписания.
    ///
    /// Идемпотентно: сначала снимаем всё, потом ставим заново. Такой подход
    /// дешевле, чем точечное сравнение планов, и исключает ситуацию, когда
    /// отменённая пара продолжает напоминать о себе.
    func reschedule(lessons: [Lesson], minutesBefore: Int, isMuted: (Lesson) -> Bool) async {
        // Снимаем только свои напоминания, не трогая чужие запросы приложения.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("lesson-") }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }

        guard minutesBefore > 0, isAuthorized else { return }

        let plan = NotificationPlanner.plan(
            lessons: lessons,
            minutesBefore: minutesBefore,
            isMuted: isMuted
        )

        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            // Напоминание о паре — не повод будить экран ночью и не «критичное»
            // уведомление: обычный приоритет.
            content.interruptionLevel = .active

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: item.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: item.id,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    /// Снять все напоминания о занятиях (выключение тумблера, смена расписания).
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("lesson-") }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    /// Пробное уведомление через несколько секунд — проверка, что доставка
    /// вообще работает на этом устройстве.
    func sendTestNotification(after seconds: TimeInterval = 5) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.test.title")
        content.body = String(localized: "notification.test.body")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(seconds, 1),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "test-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}