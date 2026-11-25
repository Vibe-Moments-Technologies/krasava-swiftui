import SwiftUI
import UIKit

/// Корневое представление: либо расписание, либо приглашение его добавить.
struct RootView: View {
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        #if DEBUG
        // CI снимает конкретные экраны: так их видно без ручной навигации.
        if ScreenshotHarness.isEnabled, ScreenshotHarness.screen != "schedule" {
            harnessScreen(ScreenshotHarness.screen)
        } else if store.hasSchedule {
            ScheduleScreen()
        } else {
            EmptyScheduleView()
        }
        #else
        if store.hasSchedule {
            ScheduleScreen()
        } else {
            EmptyScheduleView()
        }
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func harnessScreen(_ screen: String) -> some View {
        switch screen {
        case "settings":
            SettingsSheet()
        case "about":
            NavigationStack { AboutView() }
        case "lesson":
            NavigationStack {
                if let lesson = store.allLessons.first {
                    LessonDetailView(lesson: lesson)
                } else {
                    Text(verbatim: "no data")
                }
            }
        default:
            ScheduleScreen()
        }
    }
    #endif
}

/// Состояние «расписание не выбрано».
struct EmptyScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text("empty.title")
                } icon: {
                    Image(systemName: "calendar.badge.plus")
                }
            } description: {
                Text("empty.description")
            } actions: {
                Button("empty.add") { showSearch = true }
                    .buttonStyle(.glassProminent)
            }
            .navigationTitle("app.title")
            .sheet(isPresented: $showSearch) {
                SearchSheet { target in
                    showSearch = false
                    Task { await store.addTarget(target) }
                }
            }
        }
    }
}

/// Основной экран: стеклянная шапка с выбором расписания, мини-календарь и лента.
struct ScheduleScreen: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showChanges = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            VStack(spacing: 0) {
                header

                if !preferences.calendarCollapsed {
                    WeekStrip(
                        selectedDay: store.selectedDay,
                        calculator: store.weekCalculator,
                        dayTypes: store.dayTypes,
                        overrides: store.overrides,
                        twoWeeks: preferences.calendarTwoWeeks,
                        onSelect: { store.selectedDay = $0 }
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                DayPager(selectedDay: $store.selectedDay)
            }
            // Системный фон на всю площадь, включая зону домашнего индикатора:
            // без него внизу оставалась чёрная полоса окна.
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .animation(.snappy(duration: 0.25), value: preferences.calendarCollapsed)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSearch) {
                SearchSheet { target in
                    showSearch = false
                    Task { await store.addTarget(target) }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .sheet(isPresented: $showChanges) {
                ChangesSheet(changes: store.pendingChanges) {
                    store.dismissChanges()
                    showChanges = false
                }
            }
            .navigationDestination(for: Lesson.self) { lesson in
                LessonDetailView(lesson: lesson)
            }
        }
    }

    // MARK: - Шапка

    /// Стеклянная шапка. Навигационная панель скрыта намеренно: только так
    /// стекло кнопок читается как стекло, а не как стекло поверх стекла.
    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                scheduleSelector

                Spacer(minLength: 0)

                if !store.pendingChanges.isEmpty {
                    glassButton(
                        systemImage: "arrow.triangle.2.circlepath",
                        count: store.pendingChanges.count
                    ) {
                        showChanges = true
                    }
                }

                glassButton(systemImage: "arrow.clockwise", rotates: store.isLoading) {
                    Task { await store.refresh() }
                }
                .disabled(store.isLoading)

                glassButton(systemImage: "slider.horizontal.3") {
                    showSettings = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    /// Выбор расписания слева: стеклянная капсула с меню.
    private var scheduleSelector: some View {
        Menu {
            ForEach(store.savedTargets) { target in
                Button {
                    store.select(targetID: target.id)
                } label: {
                    if target.id == store.selectedTargetID {
                        Label(target.displayTitle, systemImage: "checkmark")
                    } else {
                        Text(verbatim: target.displayTitle)
                    }
                }
            }

            Divider()

            Button {
                showSearch = true
            } label: {
                Label("schedule.add", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: store.selectedTarget?.displayTitle ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: .capsule(style: .continuous))
        }
    }

    private func glassButton(
        systemImage: String,
        count: Int? = nil,
        rotates: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.accentColor, in: .capsule)
                        .offset(x: 3, y: -3)
                }
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

/// Лента дней с горизонтальным листанием.
///
/// Системный `TabView(.page)` корректно различает горизонтальный свайп ленты
/// и вертикальную прокрутку внутри дня. Держим всего три страницы вокруг
/// выбранного дня: прошлая, текущая и следующая. После свайпа центральная
/// страница пересобирается, поэтому память не растёт с числом дней.
struct DayPager: View {
    @Binding var selectedDay: DayKey
    @State private var anchorDay: DayKey
    @State private var page = 1

    init(selectedDay: Binding<DayKey>) {
        _selectedDay = selectedDay
        _anchorDay = State(initialValue: selectedDay.wrappedValue)
    }

    var body: some View {
        TabView(selection: $page) {
            DayPage(day: anchorDay.adding(days: -1)).tag(0)
            DayPage(day: anchorDay).tag(1)
            DayPage(day: anchorDay.adding(days: 1)).tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: page) { _, newPage in
            guard newPage != 1 else { return }
            let newDay = anchorDay.adding(days: newPage == 0 ? -1 : 1)
            anchorDay = newDay
            selectedDay = newDay
            recenter()
        }
        .onChange(of: selectedDay) { _, newDay in
            // Выбор даты в календаре тоже должен перестроить ленту.
            guard newDay != anchorDay else { return }
            anchorDay = newDay
            recenter()
        }
    }

    private func recenter() {
        // Без отключения анимации пейджер сначала показывает старую центральную
        // страницу и на кадр «дёргает» ленту после свайпа.
        withTransaction(Transaction(animation: nil)) {
            page = 1
        }
    }
}

/// Один день: карточки пар и разделители перемен.
struct DayPage: View {
    let day: DayKey
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        let slots = store.slots(on: day)

        Group {
            if slots.allSatisfy({ !$0.isActive }) {
                ContentUnavailableView {
                    Label {
                        Text("day.empty.title")
                    } icon: {
                        Text("🎉").font(.largeTitle)
                    }
                } description: {
                    Text("day.empty.description")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                            if index > 0 {
                                let previous = slots[index - 1]
                                let minutes = Bells.breakMinutes(from: previous.end, to: slot.start)
                                if minutes > 0 {
                                    BreakRow(
                                        minutes: minutes,
                                        start: previous.end,
                                        end: slot.start,
                                        isToday: day == ScheduleClock.today()
                                    )
                                }
                            }
                            switch slot {
                            case .active(_, _, _, let lessons):
                                ForEach(lessons) { lesson in
                                    NavigationLink(value: lesson) {
                                        LessonCard(
                                            lesson: lesson,
                                            type: store.overrides.effectiveType(for: lesson),
                                            notePreview: store.text(forLesson: lesson),
                                            isToday: day == ScheduleClock.today()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            case .empty(let bell, let start, let end):
                                EmptySlotCard(
                                    bell: bell,
                                    start: start,
                                    end: end,
                                    isToday: day == ScheduleClock.today()
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

/// Разделитель перемены с закраской прошедшей части.
struct BreakRow: View {
    let minutes: Int
    let start: TimeOfDay
    let end: TimeOfDay
    let isToday: Bool
    @Environment(Preferences.self) private var preferences

    private var label: some View {
        HStack(spacing: 6) {
            Text("•••")
            Text(verbatim: Labels.breakDuration(minutes))
            Text("•••")
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let progress = isToday && preferences.showBreakProgress
                ? TimeProgress.fractionNow(start: start, end: end, date: context.date)
                : nil

            ZStack(alignment: .leading) {
                label.foregroundStyle(.tertiary)

                if let progress {
                    // Закрашиваем сам текст слева направо, как в оригинале.
                    // Отдельная тонкая линия рядом с подписью почти не читалась
                    // и визуально не показывала, сколько перемены прошло.
                    label
                        .foregroundStyle(Color.accentColor)
                        .mask {
                            GeometryReader { geometry in
                                Rectangle()
                                    .frame(width: geometry.size.width * progress)
                                    .frame(maxHeight: .infinity, alignment: .leading)
                            }
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Карточка «нет пары».
struct EmptySlotCard: View {
    let bell: Int
    let start: TimeOfDay
    let end: TimeOfDay
    let isToday: Bool
    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack {
            Text(verbatim: "\(Labels.bell(bell)) · \(start.description)–\(end.description)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("lesson.empty")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
        .overlay(alignment: .bottom) {
            if isToday, preferences.showEmptyLessonProgress {
                LessonProgressBar(start: start, end: end)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }
        }
    }
}