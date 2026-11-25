import SwiftUI
import UIKit

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
    @State private var anchorMonday: DayKey?
    @State private var page = 1

    private var today: DayKey { ScheduleClock.today() }
    private var selectedMonday: DayKey { selectedDay.mondayOfWeek() }
    private var weekNumber: Int { calculator.weekNumber(for: selectedDay) }

    var body: some View {
        VStack(spacing: 6) {
            header
            weekPager
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        // Стеклянная подложка календаря: он лежит поверх ленты, но управляет
        // ею, поэтому управляющий слой здесь уместен.
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(spacing: 4) {
            arrowButton(systemImage: "chevron.left") { shift(weeks: -1) }

            Spacer(minLength: 0)

            // Месяц и номер недели в одной строке: две строки делали
            // мини-календарь заметно выше без новой информации.
            HStack(spacing: 6) {
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: Labels.week(weekNumber))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if !isCurrentWeek {
                Button("common.today") { onSelect(today) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
            }

            arrowButton(systemImage: "chevron.right") { shift(weeks: 1) }
        }
    }

    /// Стрелки намеренно лёгкие: в шапке календаря уже есть стеклянная
    /// подложка, и тяжёлые стеклянные кнопки внутри неё читались как
    /// отдельные панели, перегружая верх экрана.
    private func arrowButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Лента недель

    /// Системный пейджер вместо вложенного `ScrollView`: свайп по неделям
    /// больше не конкурирует с вертикальным списком пар ниже.
    private var weekPager: some View {
        let anchor = anchorMonday ?? selectedMonday

        return TabView(selection: $page) {
            weekPage(startingAt: anchor.adding(days: -7)).tag(0)
            weekPage(startingAt: anchor).tag(1)
            weekPage(startingAt: anchor.adding(days: 7)).tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: twoWeeks ? 124 : 62)
        .onAppear {
            anchorMonday = selectedMonday
        }
        .onChange(of: page) { _, newPage in
            guard newPage != 1 else { return }
            let newMonday = anchor.adding(days: newPage == 0 ? -7 : 7)
            anchorMonday = newMonday
            // Свайп меняет неделю, но не день внутри неё.
            onSelect(newMonday.adding(days: selectedDay.isoWeekday() - 1))
            recenter()
        }
        .onChange(of: selectedMonday) { _, newMonday in
            guard newMonday != anchorMonday else { return }
            anchorMonday = newMonday
            recenter()
        }
    }

    private func weekPage(startingAt monday: DayKey) -> some View {
        VStack(spacing: 6) {
            weekRow(startingAt: monday)
            if twoWeeks {
                weekRow(startingAt: monday.adding(days: 7))
            }
        }
    }

    private func recenter() {
        withTransaction(Transaction(animation: nil)) {
            page = 1
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
                    .frame(width: 28, height: 28)
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

    /// Цвет числа в выбранном дне.
    ///
    /// Не `.white`: в тёмной схеме акцент светлый, и белый текст на нём терял
    /// контраст. Системный фон даёт правильный цвет в обеих схемах — белый
    /// текст на тёмном акценте и чёрный на светлом.
    private func dayNumberColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return Color(uiColor: .systemBackground) }
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

    /// «Октябрь 2026».
    ///
    /// Системный формат для русского добавляет «г.» и оставляет месяц в
    /// нижнем регистре («октябрь 2026 г.») — в заголовке календаря это
    /// выглядит как техническая подпись, а не как название месяца.
    private var monthTitle: String {
        guard let date = selectedMonday.date() else { return "" }
        let raw = date.formatted(.dateTime.month(.wide).year())
            .replacingOccurrences(of: "г.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + raw.dropFirst()
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