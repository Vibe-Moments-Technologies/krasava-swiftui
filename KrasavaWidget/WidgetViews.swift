import SwiftUI
import WidgetKit

/// Представление виджета по размеру.
struct ScheduleWidgetView: View {
    let entry: TimelineEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let presentation = entry.presentation, !presentation.isEmpty {
                switch family {
                case .systemMedium:
                    MediumScheduleView(presentation: presentation, date: entry.date)
                case .systemLarge:
                    LargeScheduleView(presentation: presentation, date: entry.date)
                default:
                    SmallScheduleView(presentation: presentation, date: entry.date)
                }
            } else {
                EmptyWidgetView()
            }
        }
    }
}

// MARK: - Small

/// Маленький виджет: только главная пара. Ничего второстепенного —
/// на этом размере каждая строка на счету.
struct SmallScheduleView: View {
    let presentation: WidgetPresentation
    let date: Date

    var body: some View {
        if let lesson = presentation.primary {
            VStack(alignment: .leading, spacing: 0) {
                StatusLabel(status: presentation.primaryStatus)
                    .font(.caption2.weight(.bold))
                    .widgetAccentable()

                Spacer(minLength: 4)

                Text(verbatim: lesson.isRemote ? String(localized: "lesson.remote") : lesson.room)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(verbatim: "\(lesson.start)–\(lesson.end)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: 4)

                Text(verbatim: lesson.subject)
                    .font(.caption2)
                    .lineLimit(2)

                if let progress = presentation.progress {
                    ProgressCapsule(progress: progress)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Medium

/// Средний виджет: главная пара и одна следующая.
struct MediumScheduleView: View {
    let presentation: WidgetPresentation
    let date: Date

    var body: some View {
        if let lesson = presentation.primary {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    StatusLabel(status: presentation.primaryStatus)
                        .font(.caption2.weight(.bold))
                        .widgetAccentable()

                    Spacer(minLength: 0)

                    Text(verbatim: WidgetSelection.headerLabel(
                        for: DayKey(iso: lesson.date) ?? ScheduleClock.today(),
                        now: date
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: lesson.isRemote ? String(localized: "lesson.remote") : lesson.room)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(verbatim: "\(lesson.start)–\(lesson.end)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(verbatim: lesson.subject)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                if let progress = presentation.progress {
                    ProgressCapsule(progress: progress)
                }

                if let next = presentation.upcomingSameDay.first {
                    Divider()
                    NextRow(lesson: next)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Large

/// Большой виджет: главная пара и расписание дня.
struct LargeScheduleView: View {
    let presentation: WidgetPresentation
    let date: Date

    var body: some View {
        if let lesson = presentation.primary {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    StatusLabel(status: presentation.primaryStatus)
                        .font(.caption.weight(.bold))
                        .widgetAccentable()

                    Spacer(minLength: 0)

                    Text(verbatim: WidgetSelection.headerLabel(
                        for: DayKey(iso: lesson.date) ?? ScheduleClock.today(),
                        now: date
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: lesson.isRemote ? String(localized: "lesson.remote") : lesson.room)
                        .font(.title.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(verbatim: "\(lesson.start)–\(lesson.end)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(verbatim: lesson.subject)
                    .font(.headline)
                    .lineLimit(2)

                if let progress = presentation.progress {
                    ProgressCapsule(progress: progress)
                }

                let rest = presentation.upcomingSameDay
                if !rest.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rest.prefix(3)) { next in
                            NextRow(lesson: next)
                        }
                    }
                }

                if let nextDay = presentation.nextDays.first, !nextDay.lessons.isEmpty {
                    Divider()
                    Text(verbatim: nextDay.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(nextDay.lessons.prefix(2)) { next in
                        NextRow(lesson: next)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Общие элементы

/// Статус пары: «СЕЙЧАС», «ЧЕРЕЗ N МИН», «ДАЛЕЕ».
struct StatusLabel: View {
    let status: WidgetPresentation.Status?

    var body: some View {
        // Разворачиваем опционал явно: сопоставление `case .current` с
        // `Status?` не скомпилируется — нужен либо `?`, либо явный unwrap.
        if let status {
            switch status {
            case .current:
                Text("widget.status.current")
            case .soon(let minutes):
                Text(verbatim: String(format: String(localized: "widget.status.soon"), minutes))
            case .upcoming:
                Text("widget.status.next")
            }
        } else {
            Text("widget.status.next")
        }
    }
}

/// Строка следующей пары: время, аудитория, предмет.
struct NextRow: View {
    let lesson: WidgetLesson

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: lesson.start)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(verbatim: lesson.isRemote ? String(localized: "lesson.remote") : lesson.room)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(verbatim: lesson.subject)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Полоска прогресса идущей пары.
struct ProgressCapsule: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    .widgetAccentable()
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

/// Виджет без данных.
struct EmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("widget.empty.title")
                .font(.caption.weight(.semibold))
            Text("widget.empty.description")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}