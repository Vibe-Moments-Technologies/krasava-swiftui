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
                // строки — это и есть debounce без ручных таймеров.
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

// MARK: - Настройки

/// Хаб настроек: одна страница со ссылками на подразделы.
///
/// Раньше все переключатели лежали одним полотном — их стало слишком много,
/// чтобы читать список целиком.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("settings.appearance", systemImage: "circle.lefthalf.filled")
                    }

                    NavigationLink {
                        ScheduleSettingsView()
                    } label: {
                        Label("settings.schedule", systemImage: "calendar")
                    }

                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        Label("settings.notifications", systemImage: "bell")
                    }
                }

                Section {
                    NavigationLink {
                        TypesSettingsView()
                    } label: {
                        Label("settings.types", systemImage: "paintpalette")
                    }

                    NavigationLink {
                        SchedulesManagementView()
                    } label: {
                        Label("settings.schedules", systemImage: "list.bullet.rectangle")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("settings.about", systemImage: "info.circle")
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("about.copyright")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }
}

/// Оформление.
struct AppearanceSettingsView: View {
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        Form {
            Section {
                Picker("settings.theme", selection: store.preferenceBinding(\.theme)) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(verbatim: mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("settings.appearance")
            }
        }
        .navigationTitle("settings.appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Расписание.
struct ScheduleSettingsView: View {
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        Form {
            Section {
                Toggle("settings.showEmpty", isOn: store.preferenceBinding(\.showEmptyLessons))
                Toggle("settings.hideAdditional", isOn: store.preferenceBinding(\.hideAdditional))
                Toggle("settings.abbreviated", isOn: store.preferenceBinding(\.abbreviatedNames))
                Toggle("settings.autoScroll", isOn: store.preferenceBinding(\.autoScrollToCurrent))
            }

            Section {
                Toggle("settings.lessonProgress", isOn: store.preferenceBinding(\.showLessonProgress))
                Toggle("settings.breakProgress", isOn: store.preferenceBinding(\.showBreakProgress))
            } header: {
                Text("settings.progress")
            }

            Section {
                Toggle("settings.twoWeeks", isOn: store.preferenceBinding(\.calendarTwoWeeks))
                Toggle("settings.calendarCollapsed", isOn: store.preferenceBinding(\.calendarCollapsed))
            } header: {
                Text("settings.calendar")
            }
        }
        .navigationTitle("settings.schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Уведомления.
struct NotificationsSettingsView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var showDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("settings.notifications.enabled", isOn: store.preferenceBinding(\.notificationsEnabled))
                    .onChange(of: store.preferences.notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        // Разрешение спрашиваем в момент включения, а не на
                        // старте: системный диалог появляется в понятном
                        // контексте. При отказе тумблер возвращается назад,
                        // а не врёт о своём состоянии.
                        Task {
                            let granted = await LessonNotifications.shared.requestAuthorization()
                            if !granted {
                                store.preferences.notificationsEnabled = false
                                store.preferencesDidChange()
                                showDenied = true
                            }
                        }
                    }

                if store.preferences.notificationsEnabled {
                    Picker("settings.notifications.minutes", selection: store.preferenceBinding(\.notifyMinutesBefore)) {
                        ForEach(Preferences.allowedReminderMinutes, id: \.self) { minutes in
                            Text(verbatim: String(
                                format: String(localized: "settings.notifications.minutes.value"),
                                minutes
                            ))
                            .tag(minutes)
                        }
                    }

                    Button("settings.notifications.test") {
                        Task {
                            await LessonNotifications.shared.refreshAuthorizationStatus()
                            await LessonNotifications.shared.sendTestNotification()
                        }
                    }
                }
            } footer: {
                Text("settings.section.notifications.footer")
            }
        }
        .navigationTitle("settings.notifications")
        .navigationBarTitleDisplayMode(.inline)
        .alert("settings.notifications.denied.title", isPresented: $showDenied) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text("settings.notifications.denied.message")
        }
    }
}

/// Цвета типов занятий.
struct TypesSettingsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                ForEach(LessonType.settingsOrder, id: \.self) { type in
                    ColorPicker(selection: colorBinding(for: type), supportsOpacity: false) {
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
            } footer: {
                Text("settings.section.types.footer")
            }
        }
        .navigationTitle("settings.types")
        .navigationBarTitleDisplayMode(.inline)
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

/// Добавленные расписания: список с удалением.
struct SchedulesManagementView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemoval: ScheduleTarget?

    var body: some View {
        List {
            Section {
                ForEach(store.savedTargets) { target in
                    Button {
                        store.select(targetID: target.id)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: target.displayTitle)
                                    .foregroundStyle(.primary)
                                Text(verbatim: target.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if target.id == store.selectedTargetID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("settings.schedules.remove", role: .destructive) {
                            pendingRemoval = target
                        }
                    }
                }
            } footer: {
                Text("settings.schedules.footer")
            }
        }
        .navigationTitle("settings.schedules")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "settings.schedules.remove.title",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("settings.schedules.remove", role: .destructive) {
                if let target = pendingRemoval {
                    store.removeTarget(id: target.id)
                }
                pendingRemoval = nil
                if store.savedTargets.isEmpty { dismiss() }
            }
        } message: {
            Text("settings.schedules.remove.message")
        }
    }
}

// MARK: - О программе

/// Экран «О программе».
///
/// Наполнение повторяет оригинальное приложение: имя, копирайт, оговорка о
/// непричастности вуза, команда, ссылки проекта и контакты.
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private let repoURL = URL(string: "https://github.com/Vibe-Moments-Technologies/krasava-swiftui")!
    private let issuesURL = URL(string: "https://github.com/Vibe-Moments-Technologies/krasava-swiftui/issues/new")!
    private let telegramURL = URL(string: "https://t.me/krasava_app")!
    private let boostyURL = URL(string: "https://boosty.to/vibe.moments.technologies")!
    private let authorGitHubURL = URL(string: "https://github.com/l1ratch")!

    var body: some View {
        Form {
            headerSection
            teamSection
            linksSection
            contactSection
        }
        .navigationTitle("settings.about")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 84, height: 84)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 20))

                Text("app.title")
                    .font(.title3.weight(.bold))

                Text(verbatim: AppInfo.versionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("about.copyright")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("about.disclaimer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var teamSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Линк (l1ratch)")
                        .font(.body.weight(.medium))
                    Text("about.team.role")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("connect@l1ratch.ru", destination: URL(string: "mailto:connect@l1ratch.ru")!)
                        .font(.caption)
                }

                Spacer(minLength: 0)

                Button {
                    openURL(authorGitHubURL)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("about.team")
        } footer: {
            Text("about.team.footer")
        }
    }

    private var linksSection: some View {
        Section {
            Button {
                openURL(repoURL)
            } label: {
                Label("about.link.repository", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Button {
                openURL(telegramURL)
            } label: {
                Label("about.link.telegram", systemImage: "paperplane")
            }
            Button {
                openURL(boostyURL)
            } label: {
                Label("about.link.boosty", systemImage: "heart")
            }
        } header: {
            Text("about.links")
        }
    }

    private var contactSection: some View {
        Section {
            Button {
                openURL(issuesURL)
            } label: {
                Label("about.contact.issue", systemImage: "exclamationmark.bubble")
            }
        } header: {
            Text("about.contact")
        } footer: {
            Text("about.contact.footer")
        }
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

/// Сведения о сборке.
enum AppInfo {
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

// MARK: - Биндинги настроек

extension ScheduleStore {
    /// Привязка к настройке, которая после записи пересобирает производные
    /// данные. Без этого переключатель «скрывать доп. занятия» менял бы
    /// значение, но лента не обновлялась.
    func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<Preferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.preferences[keyPath: keyPath] },
            set: { newValue in
                self.preferences[keyPath: keyPath] = newValue
                self.preferencesDidChange()
            }
        )
    }
}