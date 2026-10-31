import SwiftUI

/// Мини-календарь: неделя (или две) с точками занятий.
///
/// Недели листаются свайпом — как в системном календаре. Стрелки остались как
/// дополнительный способ: ими удобно целиться на одну неделю, а свайпом
/// быстрее пролистать месяц.
struct WeekStrip: View {
    let selectedDay: DayKey
    let calculator: WeekCalculator
    let dayTypes: [DayKey: [LessonType]]
    let overrides: UserOverrides
    let twoWeeks: Bool
    let onSelect: (DayKey) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var scrolledWeek: DayKey?

    private var today: DayKey { ScheduleClock.today() }
    private var selectedMonday: DayKey { selectedDay.mondayOfWeek() }
    private var weekNumber: Int { calculator.weekNumber(for: selectedDay) }

    /// Понедельники в пределах примерно года в обе стороны.
    private var weeks: [DayKey] {
        let base = today.mondayOfWeek()
        let offset = base.days(until: selectedMonday) / 7
        let lower = max(min(offset, 0), -52)
        let upper = min(max(offset, 0), 52)
        return (lower...upper).map { base.adding(days: $0 * 7) }
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            weekPager
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        // Стеклянная подложка календаря: он лежит поверх ленты, но управляет
        // ею, поэтому управляющий слой здесь уместен.
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(spacing: 4) {
            arrowButton(systemImage: "chevron.left") { shift(weeks: -1) }

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
                Button("common.today") { onSelect(today) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
            }

            arrowButton(systemImage: "chevron.right") { shift(weeks: 1) }
        }
    }

    private func arrowButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
    }

    // MARK: - Лента недель

    private var weekPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(weeks, id: \.self) { monday in
                    VStack(spacing: 6) {
                        weekRow(startingAt: monday)
                        if twoWeeks {
                            weekRow(startingAt: monday.adding(days: 7))
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(monday)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledWeek)
        .scrollIndicators(.hidden)
        .frame(height: twoWeeks ? 132 : 66)
        .onAppear { scrolledWeek = selectedMonday }
        .onChange(of: scrolledWeek) { _, newValue in
            // Свайп меняет неделю, но не день внутри неё: сохраняем день недели.
            guard let newValue else { return }
            let weekdayOffset = selectedDay.isoWeekday() - 1
            let day = newValue.adding(days: weekdayOffset)
            if day != selectedDay { onSelect(day) }
        }
        .onChange(of: selectedMonday) { _, newValue in
            if scrolledWeek != newValue { scrolledWeek = newValue }
        }
    }

    private func weekRow(startingAt first: DayKey) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { offset in
                dayCell(first.adding(days: offset))
            }
        }
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

    /// До пяти точек в строке, остальное — во второй.
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
        today.mondayOfWeek() == selectedMonday
    }

    private var monthTitle: String {
        guard let date = selectedMonday.date() else { return "" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func weekdayName(_ day: DayKey) -> String {
        guard let date = day.date() else { return "" }
        // Двухбуквенная подпись («Пн») без собственного словаря дней недели:
        // берём узкий локализованный формат и обрезаем.
        let formatted = date.formatted(.dateTime.weekday(.abbreviated))
        return String(formatted.prefix(2))
    }

    private func shift(weeks: Int) {
        onSelect(selectedDay.adding(days: weeks * 7))
    }
}