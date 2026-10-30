import SwiftUI

/// Корневое представление: либо расписание, либо приглашение его добавить.
struct RootView: View {
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        if store.hasSchedule {
            ScheduleScreen()
        } else {
            EmptyScheduleView()
        }
    }
}

/// Состояние «расписание не выбрано».
///
/// Отдельный экран, а не пустой список: пользователь должен понимать, что
/// нужно сделать, а не гадать, почему лента пустая.
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
                    Task { await store.select(target) }
                }
            }
        }
    }
}

/// Основной экран: мини-календарь и лента дня.
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
                if !preferences.calendarCollapsed {
                    WeekStrip(
                        selectedDay: store.selectedDay,
                        calculator: store.weekCalculator,
                        dayTypes: store.dayTypeSummary,
                        overrides: store.overrides,
                        twoWeeks: preferences.calendarTwoWeeks,
                        onSelect: { store.selectedDay = $0 }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                DayPager(selectedDay: $store.selectedDay)
            }
            .animation(.snappy(duration: 0.25), value: preferences.calendarCollapsed)
            .navigationTitle(store.target?.displayTitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSearch) {
                SearchSheet { target in
                    showSearch = false
                    Task { await store.select(target) }
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
            .overlay(alignment: .bottom) { floatingBar }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !store.pendingChanges.isEmpty {
                Button {
                    showChanges = true
                } label: {
                    Label {
                        Text("changes.title")
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showSearch = true
                } label: {
                    Label("schedule.change", systemImage: "magnifyingglass")
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("schedule.refresh", systemImage: "arrow.clockwise")
                }
                Divider()
                Button {
                    showSettings = true
                } label: {
                    Label("settings.title", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// Плавающая панель управления. Стекло здесь уместно: это управляющий
    /// слой поверх контента, а не сам контент.
    private var floatingBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                let isToday = store.selectedDay == ScheduleClock.today()
                if !isToday {
                    Button {
                        store.selectedDay = ScheduleClock.today()
                    } label: {
                        Label("common.today", systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glass)
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Label("schedule.refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(store.isLoading)
            }
            .padding(6)
        }
        .padding(.bottom, 12)
    }
}

/// Лента дней с горизонтальным листанием.
///
/// Бесконечная в обе стороны идея из оригинала сохранена, но реализована
/// окном ±100 дней: этого достаточно, чтобы листать семестр в обе стороны,
/// и при этом не держать сотни страниц в памяти.
struct DayPager: View {
    @Binding var selectedDay: DayKey
    @Environment(ScheduleStore.self) private var store

    private static let span = 100

    @State private var page: Int

    init(selectedDay: Binding<DayKey>) {
        _selectedDay = selectedDay
        let today = ScheduleClock.today()
        _page = State(
            initialValue: min(max(Self.span + today.days(until: selectedDay.wrappedValue), 0), Self.span * 2)
        )
    }

    var body: some View {
        let today = ScheduleClock.today()

        TabView(selection: $page) {
            ForEach(0...(Self.span * 2), id: \.self) { index in
                DayPage(day: today.adding(days: index - Self.span))
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: page) { _, newValue in
            let day = today.adding(days: newValue - Self.span)
            if day != selectedDay { selectedDay = day }
        }
        .onChange(of: selectedDay) { _, newValue in
            let offset = today.days(until: newValue)
            let target = min(max(Self.span + offset, 0), Self.span * 2)
            if target != page { page = target }
        }
    }
}

/// Один день: карточки пар и разделители перемен.
struct DayPage: View {
    let day: DayKey
    @Environment(ScheduleStore.self) private var store
    @Environment(Preferences.self) private var preferences

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
                                EmptySlotCard(bell: bell, start: start, end: end)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
            }
        }
    }
}

/// Разделитель перемены.
struct BreakRow: View {
    let minutes: Int
    let start: TimeOfDay
    let end: TimeOfDay
    let isToday: Bool
    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: 6) {
            Text("•••")
            Text(verbatim: Labels.breakDuration(minutes))
            Text("•••")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .overlay(alignment: .leading) { progressOverlay }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if isToday, preferences.showBreakProgress {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = Self.minutes(of: context.date)
                if now >= start.minutesSinceMidnight, now < end.minutesSinceMidnight {
                    GeometryReader { geometry in
                        let total = max(end.minutesSinceMidnight - start.minutesSinceMidnight, 1)
                        let passed = Double(now - start.minutesSinceMidnight) / Double(total)
                        Capsule()
                            .fill(Color.accentColor.opacity(0.25))
                            .frame(width: geometry.size.width * passed)
                    }
                    .frame(height: 2)
                }
            }
        }
    }

    private static func minutes(of date: Date) -> Int {
        let calendar = ScheduleClock.calendar
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

/// Карточка «нет пары».
struct EmptySlotCard: View {
    let bell: Int
    let start: TimeOfDay
    let end: TimeOfDay

    var body: some View {
        HStack {
            Text(verbatim: Labels.bell(bell) + " · \(start.description)–\(end.description)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("lesson.empty")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
    }
}