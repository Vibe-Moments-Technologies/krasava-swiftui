import SwiftUI
import UIKit

/// Карточка занятия в ленте дня.
struct LessonCard: View {
    let lesson: Lesson
    /// Тип с учётом пользовательских переопределений — считается в сторе,
    /// чтобы карточка не знала про иерархию приоритетов.
    let type: LessonType
    let notePreview: String
    let isToday: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(ScheduleStore.self) private var store
    @Environment(Preferences.self) private var preferences

    private var accent: Color {
        TypePalette.color(for: type, overrides: store.overrides, scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            subject
            details
            if !notePreview.isEmpty { note }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .overlay(alignment: .bottom) {
            if isToday, preferences.showLessonProgress {
                LessonProgressBar(start: lesson.start, end: lesson.end)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(verbatim: Labels.bell(lesson.bell))
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(accent.opacity(0.14), in: .rect(cornerRadius: 7))

            Text(verbatim: "\(lesson.start.description)–\(lesson.end.description)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 0)

            Text(verbatim: type.badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(TypePalette.badgeBackground(for: type, overrides: store.overrides, scheme: colorScheme), in: .capsule)
        }
    }

    private var subject: some View {
        Text(verbatim: preferences.abbreviatedNames ? Self.abbreviate(lesson.subject) : lesson.subject)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(2)
    }

    @ViewBuilder
    private var details: some View {
        if !lesson.teachers.isEmpty {
            Label {
                Text(verbatim: lesson.teachers.joined(separator: ", "))
            } icon: {
                Image(systemName: "person")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        if lesson.isRemote {
            Label {
                Text("lesson.remote")
            } icon: {
                Image(systemName: "video")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        } else if !lesson.physicalRooms.isEmpty {
            Label {
                Text(verbatim: lesson.physicalRooms.joined(separator: ", "))
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "note.text")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: notePreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }

    /// Сокращение названия предмета по первым буквам слов.
    ///
    /// Не обрезка: «Базы данных» → «БД», а не «Базы да…». Названия из двух
    /// слов и короче не трогаем — сокращение сделало бы их непонятнее.
    static func abbreviate(_ subject: String) -> String {
        let words = subject.split(whereSeparator: \.isWhitespace)
        guard words.count > 2 else { return subject }
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Полоска прогресса идущей пары.
///
/// Обновляется по таймеру раз в минуту, но только когда пара действительно
/// идёт: до и после неё полоски нет вовсе.
struct LessonProgressBar: View {
    let start: TimeOfDay
    let end: TimeOfDay

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = Self.minutes(of: context.date)
            bar(now: now)
        }
    }

    @ViewBuilder
    private func bar(now: Int) -> some View {
        let from = start.minutesSinceMidnight
        let to = end.minutesSinceMidnight

        if to > from, now >= from, now < to {
            let progress = Double(now - from) / Double(to - from)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 2.5)
            .padding(.top, 4)
        }
    }

    private static func minutes(of date: Date) -> Int {
        let calendar = ScheduleClock.calendar
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}