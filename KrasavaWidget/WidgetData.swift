import Foundation

/// Чтение снимка расписания из общего контейнера.
///
/// Виджет никогда не ходит в сеть: расширение живёт в жёстких лимитах памяти и
/// времени, и сетевой запрос здесь — прямой путь к пустому виджету. Всё, что
/// нужно, приложение записывает заранее.
enum WidgetData {

    /// Причина отсутствия данных.
    ///
    /// Разные причины — разные сообщения. «Нет занятий» и «нет данных» нельзя
    /// показывать одинаково: в первом случае всё в порядке, во втором нужно
    /// открыть приложение.
    enum LoadResult {
        case noAppGroup
        case noData
        case badData
        case ok(WidgetSnapshot)
    }

    static func load() -> LoadResult {
        guard let defaults = AppGroup.defaults() else { return .noAppGroup }
        guard let json = defaults.string(forKey: AppGroup.snapshotKey) else { return .noData }
        guard let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.isCompatible else { return .badData }
        return .ok(snapshot)
    }
}

/// Построение таймлайна.
///
/// Расписание предсказуемо, поэтому точки обновления считаются заранее — это
/// рекомендованный Apple подход. Записи ставятся на значимых границах: начало
/// и конец пары, момент «скоро», полночь и шаги прогресса.
enum WidgetTimelineBuilder {
    /// Потолок записей. Больше система всё равно не покажет, а лишние записи
    /// только замедляют перезагрузку.
    static let maxEntries = 64
    /// Шаг полосы прогресса идущей пары.
    static let progressStepMinutes = 15

    static func entries(now: Date = Date(), calendar: Calendar = ScheduleClock.calendar) -> [ScheduleWidgetEntry] {
        var moments: [Date] = [now]

        if case .ok(let snapshot) = WidgetData.load() {
            for lesson in snapshot.lessons {
                guard let start = WidgetSelection.startDate(lesson, calendar: calendar),
                      let end = WidgetSelection.endDate(lesson, calendar: calendar) else { continue }

                if start > now { moments.append(start) }
                if end > now { moments.append(end) }

                let soon = start.addingTimeInterval(
                    -Double(WidgetSelection.soonThresholdMinutes) * 60
                )
                if soon > now { moments.append(soon) }

                // Шаги прогресса — только для пар, которые идут или начнутся
                // в ближайшие 12 часов: иначе таймлайн распухнет.
                guard end > now, start < now.addingTimeInterval(12 * 3600) else { continue }
                let step = Double(progressStepMinutes) * 60
                var moment = max(now, start)
                let elapsed = moment.timeIntervalSince(start)
                moment = moment.addingTimeInterval(
                    step - elapsed.truncatingRemainder(dividingBy: step)
                )
                while moment < end {
                    moments.append(moment)
                    moment = moment.addingTimeInterval(step)
                }
            }
        }

        // Полночь меняет подпись дня («СЕГОДНЯ» → дата) и активную пару.
        for offset in 1...3 {
            let midnight = calendar.startOfDay(for: now).addingTimeInterval(Double(offset) * 86400)
            moments.append(midnight)
        }

        // Близкие моменты склеиваются: WidgetKit не любит записей вплотную.
        let unique = Array(Set(moments.map { $0.timeIntervalSince1970.rounded() })).sorted()
        var chosen: [Date] = []
        for value in unique {
            let date = Date(timeIntervalSince1970: value)
            if let last = chosen.last, date.timeIntervalSince(last) < 30 { continue }
            chosen.append(date)
        }

        return chosen.prefix(maxEntries).map { moment in
            ScheduleWidgetEntry(date: moment, presentation: presentation(at: moment, calendar: calendar))
        }
    }

    private static func presentation(at moment: Date, calendar: Calendar) -> WidgetPresentation? {
        switch WidgetData.load() {
        case .ok(let snapshot):
            return WidgetSelection.make(snapshot: snapshot, now: moment, calendar: calendar)
        default:
            return nil
        }
    }
}