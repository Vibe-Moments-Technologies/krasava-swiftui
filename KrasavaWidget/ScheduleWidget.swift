import SwiftUI
import WidgetKit

/// Запись таймлайна: готовое состояние на конкретный момент.
struct TimelineEntry: TimelineEntry {
    let date: Date
    let presentation: WidgetPresentation?
}

/// Провайдер виджета расписания.
struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimelineEntry {
        TimelineEntry(date: Date(), presentation: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimelineEntry) -> Void) {
        let now = Date()
        let presentation: WidgetPresentation?
        if case .ok(let snapshot) = WidgetData.load() {
            presentation = WidgetSelection.make(snapshot: snapshot, now: now)
        } else {
            presentation = nil
        }
        completion(TimelineEntry(date: now, presentation: presentation))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimelineEntry>) -> Void) {
        let entries = WidgetTimelineBuilder.entries()
        // `.atEnd` — система вернётся за новым таймлайном после последней записи.
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Виджет расписания.
struct ScheduleWidget: Widget {
    static let kind = "KrasavaScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Системный фон, а не собственный цвет: виджет должен
                    // выглядеть как родной виджет iOS, включая тонирование.
                    Color.clear
                }
        }
        .configurationDisplayName("widget.title")
        .description("widget.description")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Точка входа расширения.
@main
struct KrasavaWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
    }
}