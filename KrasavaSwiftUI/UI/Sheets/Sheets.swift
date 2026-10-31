import SwiftUI

/// Поиск и выбор расписания.
struct SearchSheet: View {
    let onSelect: (ScheduleTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ScheduleTarget] = []
    @State private var isSearching = false
    @State private var failed = false

    private let api = ScheduleAPI()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("search.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("common.cancel") { dismiss() }
                    }
                }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("search.prompt")
                )
                // `task(id:)` отменяет предыдущую задачу при каждом изменении
                // строки — это и есть debounce без ручных таймеров и флагов.
                .task(id: query) {
                    await search()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            ContentUnavailableView {
                Label {
                    Text("search.hint.title")
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
            } description: {
                Text("search.hint.description")
            }
        } else if isSearching && results.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if failed && results.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("search.failed.title")
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                }
            } description: {
                Text("search.failed.description")
            } actions: {
                Button("common.retry") {
                    Task { await search() }
                }
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results) { target in
                Button {
                    onSelect(target)
                } label: {
                    row(for: target)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func row(for target: ScheduleTarget) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: target.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if target.fullTitle != target.displayTitle {
                    Text(verbatim: target.fullTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: target.kind.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: .capsule)
        }
        .contentShape(.rect)
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            failed = false
            return
        }

        // Пауза, чтобы не ходить в сеть на каждое нажатие клавиши.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let found = try await api.search(match: trimmed)
            guard !Task.isCancelled else { return }
            results = found
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            failed = true
        }
    }
}

/// Настройки: одна шторка, три смысловые группы.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var showRemoveConfirmation = false
    @State private var showNotificationsDenied = false

    var body: some View {
        @Bindable var preferences = store.preferences

        NavigationStack {
            Form {
                appearanceSection(preferences)
                scheduleSection(preferences)
                notificationsSection(preferences)
                typesSection
                hiddenSubjectsSection
                aboutSection
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                }
            }
            .confirmationDialog(
                "settings.remove.title",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("settings.remove.confirm", role: .destructive) {
                    store.removeSchedule()
                    dismiss()
                }
            } message: {
                Text("settings.remove.message")
            }
        }
    }

    // MARK: - Секции

    private func appearanceSection(_ preferences: Preferences) -> some View {
        @Bindable var preferences = preferences
        return Section {
            Picker("settings.theme", selection: $preferences.theme) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(verbatim: mode.displayName).tag(mode)
                }
            }
        } header: {
            Text("settings.section.appearance")
        }
    }

    private func scheduleSection(_ preferences: Preferences) -> some View {
        @Bindable var preferences = preferences
        return Section {
            Toggle("settings.showEmpty", isOn: $preferences.showEmptyLessons)
            Toggle("settings.hideAdditional", isOn: $preferences.hideAdditional)
            Toggle("settings.abbreviated", isOn: $preferences.abbreviatedNames)
            Toggle("settings.autoScroll", isOn: $preferences.autoScrollToCurrent)
            Toggle("settings.lessonProgress", isOn: $preferences.showLessonProgress)
            Toggle("settings.breakProgress", isOn: $preferences.showBreakProgress)
            Toggle("settings.twoWeeks", isOn: $preferences.calendarTwoWeeks)
            Toggle("settings.calendarCollapsed", isOn: $preferences.calendarCollapsed)
        } header: {
            Text("settings.section.schedule")
        }
    }

    private func notificationsSection(_ preferences: Preferences) -> some View {
        @Bindable var preferences = preferences

        return Section {
            Toggle("settings.notifications.enabled", isOn: $preferences.notificationsEnabled)
                .onChange(of: preferences.notificationsEnabled) { _, enabled in
                    guard enabled else { return }
                    // Разрешение спрашиваем в момент включения тумблера, а не
                    // на старте: так системный диалог появляется в понятном
                    // контексте. Если пользователь откажет — тумблер вернётся
                    // в выключенное состояние, а не будет врать.
                    Task {
                        let granted = await LessonNotifications.shared.requestAuthorization()
                        if !granted {
                            preferences.notificationsEnabled = false
                            showNotificationsDenied = true
                        }
                    }
                }

            if preferences.notificationsEnabled {
                Picker("settings.notifications.minutes", selection: $preferences.notifyMinutesBefore) {
                    ForEach(Preferences.allowedReminderMinutes, id: \.self) { minutes in
                        Text(verbatim: Self.minutesLabel(minutes)).tag(minutes)
                    }
                }
                Button("settings.notifications.test") {
                    Task {
                        await LessonNotifications.shared.refreshAuthorizationStatus()
                        await LessonNotifications.shared.sendTestNotification()
                    }
                }
            }
        } header: {
            Text("settings.section.notifications")
        } footer: {
            Text("settings.section.notifications.footer")
        }
        .alert("settings.notifications.denied.title", isPresented: $showNotificationsDenied) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text("settings.notifications.denied.message")
        }
    }

    /// «За 10 мин» — без склонений: подпись одинакова для всех чисел.
    private static func minutesLabel(_ minutes: Int) -> String {
        String(format: String(localized: "settings.notifications.minutes.value"), minutes)
    }

    private var typesSection: some View {
        Section {
            ForEach(LessonType.settingsOrder, id: \.self) { type in
                ColorPicker(
                    selection: colorBinding(for: type),
                    supportsOpacity: false
                ) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(TypePalette.color(
                                for: type,
                                overrides: store.overrides,
                                scheme: colorScheme
                            ))
                            .frame(width: 10, height: 10)
                        Text(verbatim: type.displayName)
                    }
                }
            }

            if !store.overrides.typeColors.isEmpty {
                Button("settings.types.reset") {
                    var updated = store.overrides
                    updated.typeColors.removeAll()
                    store.overrides = updated
                }
            }
        } header: {
            Text("settings.section.types")
        } footer: {
            Text("settings.section.types.footer")
        }
    }

    @ViewBuilder
    private var hiddenSubjectsSection: some View {
        if !store.overrides.hiddenSubjects.isEmpty {
            Section {
                ForEach(Array(store.overrides.hiddenSubjects).sorted(), id: \.self) { subject in
                    HStack {
                        Text(verbatim: subject)
                        Spacer()
                        Button("settings.hidden.unhide") {
                            var updated = store.overrides
                            updated.hiddenSubjects.remove(subject)
                            store.overrides = updated
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("settings.section.hidden")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("settings.about.version") {
                Text(verbatim: AppInfo.versionDescription)
            }
            LabeledContent("settings.about.source") {
                Text("settings.about.source.value")
            }
            Button("settings.remove.title", role: .destructive) {
                showRemoveConfirmation = true
            }
        } header: {
            Text("settings.section.about")
        } footer: {
            Text("settings.about.footer")
        }
    }

    private func colorBinding(for type: LessonType) -> Binding<Color> {
        Binding(
            get: {
                let hex = store.overrides.color(for: type)?.hex
                    ?? TypePalette.defaultHex(for: type, dark: colorScheme == .dark)
                return Color(rgb: hex)
            },
            set: { newValue in
                guard let hex = newValue.rgbHex else { return }
                var updated = store.overrides
                updated.setColor(TypeColor(hex: hex), for: type)
                store.overrides = updated
            }
        )
    }
}

/// Что изменилось после обновления расписания.
struct ChangesSheet: View {
    let changes: [ScheduleChange]
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if changes.isEmpty {
                    ContentUnavailableView(
                        "changes.empty.title",
                        systemImage: "checkmark.circle",
                        description: Text("changes.empty.description")
                    )
                } else {
                    List(changes) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: icon(for: change.kind))
                                    .foregroundStyle(tint(for: change.kind))
                                Text(verbatim: change.subject)
                                    .font(.body.weight(.medium))
                                Spacer(minLength: 0)
                                Text(verbatim: Labels.bell(change.bell))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let date = change.day.date() {
                                Text(verbatim: date.formatted(.dateTime.day().month(.wide).weekday(.abbreviated)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(change.details.enumerated()), id: \.offset) { _, detail in
                                Text(verbatim: detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("changes.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }

    private func icon(for kind: ScheduleChangeKind) -> String {
        switch kind {
        case .added:     "plus.circle"
        case .modified:  "arrow.triangle.2.circlepath"
        case .cancelled: "minus.circle"
        }
    }

    private func tint(for kind: ScheduleChangeKind) -> Color {
        switch kind {
        case .added:     .green
        case .modified:  .orange
        case .cancelled: .red
        }
    }
}

/// Сведения о сборке для экрана «О приложении».
enum AppInfo {
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}