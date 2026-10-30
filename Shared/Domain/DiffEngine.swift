import Foundation

/// Тип изменения в расписании.
enum ScheduleChangeKind: String, Codable, Sendable {
    case added
    case modified
    case cancelled
}

/// Одно изменение: что именно поменялось между обновлениями.
struct ScheduleChange: Identifiable, Hashable, Sendable {
    let kind: ScheduleChangeKind
    let day: DayKey
    let bell: Int
    let subject: String
    /// Человекочитаемое описание правки: «ауд: В-78 → С-20». Для добавленных
    /// и отменённых — короткая подпись.
    let details: [String]

    var id: String { "\(kind.rawValue)-\(day)-\(bell)-\(subject)" }
}

/// Сравнение расписаний до и после обновления.
///
/// Нужен, чтобы студент видел переносы и отмены, а не искал их глазами по
/// всему семестру. Правила сравнения:
///  * ключ — дата + номер пары + предмет в нижнем регистре, чтобы смена
///    регистра или лишний пробел не выглядели как отмена и добавление;
///  * изменения преподавателя, аудитории и времени считаются правкой, а не
///    отменой с добавлением: так пользователю понятнее.
enum DiffEngine {

    /// Все изменения между двумя наборами занятий.
    /// Возвращает пустой массив, если ничего не поменялось.
    static func diff(
        old: [Lesson],
        new: [Lesson],
        from window: ClosedRange<DayKey>
    ) -> [ScheduleChange] {
        let oldIndex = index(old, in: window)
        let newIndex = index(new, in: window)

        var changes: [ScheduleChange] = []

        for (key, newLessons) in newIndex {
            guard let oldLessons = oldIndex[key] else {
                for lesson in newLessons {
                    changes.append(
                        ScheduleChange(
                            kind: .added,
                            day: lesson.day,
                            bell: lesson.bell,
                            subject: lesson.subject,
                            details: [detail(for: lesson)]
                        )
                    )
                }
                continue
            }
            guard let previous = oldLessons.first, let current = newLessons.first else { continue }
            let differences = modifications(from: previous, to: current)
            if !differences.isEmpty {
                changes.append(
                    ScheduleChange(
                        kind: .modified,
                        day: current.day,
                        bell: current.bell,
                        subject: current.subject,
                        details: differences
                    )
                )
            }
        }

        for (key, oldLessons) in oldIndex where newIndex[key] == nil {
            for lesson in oldLessons {
                changes.append(
                    ScheduleChange(
                        kind: .cancelled,
                        day: lesson.day,
                        bell: lesson.bell,
                        subject: lesson.subject,
                        details: [String(localized: "diff.detail.cancelled")]
                    )
                )
            }
        }

        return changes.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.bell != rhs.bell { return lhs.bell < rhs.bell }
            return lhs.subject < rhs.subject
        }
    }

    // MARK: - Внутреннее

    private struct Key: Hashable {
        let day: DayKey
        let bell: Int
        let subject: String
    }

    private static func index(_ lessons: [Lesson], in window: ClosedRange<DayKey>) -> [Key: [Lesson]] {
        var result: [Key: [Lesson]] = [:]
        for lesson in lessons where window.contains(lesson.day) {
            let key = Key(day: lesson.day, bell: lesson.bell, subject: normalize(lesson.subject))
            result[key, default: []].append(lesson)
        }
        return result
    }

    private static func modifications(from old: Lesson, to new: Lesson) -> [String] {
        var details: [String] = []
        if old.rooms != new.rooms {
            details.append(
                String(
                    format: String(localized: "diff.detail.room"),
                    joinOrDash(old.rooms),
                    joinOrDash(new.rooms)
                )
            )
        }
        if old.teachers != new.teachers {
            details.append(
                String(
                    format: String(localized: "diff.detail.teacher"),
                    joinOrDash(old.teachers),
                    joinOrDash(new.teachers)
                )
            )
        }
        if old.start != new.start {
            details.append(
                String(
                    format: String(localized: "diff.detail.time"),
                    old.start.description,
                    new.start.description
                )
            )
        }
        return details
    }

    private static func detail(for lesson: Lesson) -> String {
        if lesson.isRemote {
            return String(
                format: String(localized: "diff.detail.added.remote"),
                lesson.bell
            )
        }
        return String(
            format: String(localized: "diff.detail.added"),
            lesson.bell,
            joinOrDash(lesson.physicalRooms)
        )
    }

    private static func joinOrDash(_ values: [String]) -> String {
        values.isEmpty ? "—" : values.joined(separator: ", ")
    }

    private static func normalize(_ subject: String) -> String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}