import SwiftUI

/// Мини-календарь: неделя (или две) с точками занятий.
///
/// Показывает ровно ту неделю, в которую попадает выбранный день. Стрелки
/// сдвигают выбор на неделю — так календарь и лента всегда согласованы, и
/// невозможно «уехать» календарём в одну сторону, а лентой в другую.
struct WeekStrip: View {
    let selectedDay: DayKey
    let calculator: WeekCalculator
    let dayTypes: [DayKey: [LessonType]]
    let overrides: UserOverrides
    let twoWeeks: Bool
    let onSelect: (DayKey) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(Preferences.self) private var preferences

    private var today: DayKey { ScheduleClock.today() }
    private var monday: DayKey { selectedDay.mondayOfWeek() }
    private var weekNumber: Int { calculator.weekNumber(for: selectedDay) }

    var body: some View {
        VStack(spacing: 8) {
            header
            rows
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                shift(weeks: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 32)

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: Labels.week(weekNumber))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !isCurrentWeek {
                Button("common.today") {
                    onSelect(today)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
            }

            Button {
                shift(weeks: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 32)
        }
        .padding(.horizontal, 12)
    }

    private var rows: some View {
        VStack(spacing: 6) {
            weekRow(startingAt: monday)
            if twoWeeks {
                weekRow(startingAt: monday.adding(days: 7))
            }
        }
    }

    private func weekRow(startingAt first: DayKey) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { offset in
                dayCell(first.adding(days: offset))
            }
        }
        .padding(.horizontal, 8)
    }

    private func dayCell(_ day: DayKey) -> some View {
        let isSelected = day == selectedDay
        let isToday = day == today
        let types = dayTypes[day] ?? []

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 3) {
                Text(weekdayName(day))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected || isToday ? Color.accentColor : .secondary)

                Text("\(day.day)")
                    .font(.system(size: 15, weight: isSelected || isToday ? .bold : .semibold))
                    .foregroundStyle(dayNumberColor(isSelected: isSelected, isToday: isToday))
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle()
                                .fill(Color.accentColor.opacity(0.14))
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                        }
                    }

                dots(for: types)
                    .frame(height: 12)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func dayNumberColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }

    /// До пяти точек в строке, остальное — во второй. Больше двух строк
    /// в мини-календаре не бывает: в дне не бывает 12 пар.
    private func dots(for types: [LessonType]) -> some View {
        let firstRow = Array(types.prefix(5))
        let secondRow = Array(types.dropFirst(5).prefix(5))

        return VStack(spacing: 2) {
            if !firstRow.isEmpty { dotRow(firstRow) }
            if !secondRow.isEmpty { dotRow(secondRow) }
        }
    }

    private func dotRow(_ types: [LessonType]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(types.enumerated()), id: \.offset) { _, type in
                Circle()
                    .fill(TypePalette.color(for: type, overrides: overrides, scheme: colorScheme))
                    .frame(width: 4.5, height: 4.5)
            }
        }
    }

    private var isCurrentWeek: Bool {
        today.mondayOfWeek() == monday
    }

    private var monthTitle: String {
        let date = monday.date()
        guard let date else { return "" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func weekdayName(_ day: DayKey) -> String {
        guard let date = day.date() else { return "" }
        // `.veryShort` даёт «П», «В»; нужен двухбуквенный «Пн» — берём
        // узкий формат и обрезаем до двух символов, чтобы не заводить
        // собственный словарь дней недели.
        let formatted = date.formatted(.dateTime.weekday(.abbreviated))
        return String(formatted.prefix(2))
    }

    private func shift(weeks: Int) {
        onSelect(selectedDay.adding(days: weeks * 7))
    }
}