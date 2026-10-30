import SwiftUI

/// Детали пары: всё про занятие и действия над ним.
///
/// Здесь же реализованы две вещи, которых не было в оригинале в таком виде:
/// заметка к паре прямо на экране (без отдельного раздела) и переопределение
/// типа занятия.
struct LessonDetailView: View {
    let lesson: Lesson

    @Environment(ScheduleStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var noteText: String = ""
    @State private var didLoadNote = false

    private var type: LessonType { store.overrides.effectiveType(for: lesson) }
    private var accent: Color {
        TypePalette.color(for: type, overrides: store.overrides, scheme: colorScheme)
    }

    var body: some View {
        Form {
            infoSection
            typeSection
            noteSection
            actionsSection
        }
        .navigationTitle(lesson.subject)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadNote)
        .onDisappear(perform: saveNote)
    }

    // MARK: - Секции

    private var infoSection: some View {
        Section {
            LabeledContent("detail.time") {
                Text(verbatim: "\(lesson.start.description)–\(lesson.end.description)")
                    .monospacedDigit()
            }
            LabeledContent("detail.bell") {
                Text(verbatim: Labels.bell(lesson.bell))
            }
            LabeledContent("detail.day") {
                Text(verbatim: formattedDay)
            }
            if !lesson.teachers.isEmpty {
                LabeledContent("detail.teacher") {
                    Text(verbatim: lesson.teachers.joined(separator: ", "))
                }
            }
            if lesson.isRemote {
                LabeledContent("detail.room") {
                    Text("lesson.remote")
                }
            } else if !lesson.physicalRooms.isEmpty {
                LabeledContent("detail.room") {
                    Text(verbatim: lesson.physicalRooms.joined(separator: ", "))
                }
            }
            if lesson.groups.count > 1 {
                LabeledContent("detail.groups") {
                    Text(verbatim: lesson.groups.joined(separator: ", "))
                }
            }
        } header: {
            Text("detail.section.info")
        }
    }

    private var typeSection: some View {
        Section {
            Menu {
                Button {
                    setType(nil)
                } label: {
                    Label("type.auto", systemImage: "wand.and.stars")
                }

                Divider()

                ForEach(LessonType.settingsOrder, id: \.self) { candidate in
                    Button {
                        setType(candidate)
                    } label: {
                        if candidate == type {
                            Label(candidate.displayName, systemImage: "checkmark")
                        } else {
                            Text(candidate.displayName)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("detail.type")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: type.displayName)
                        .foregroundStyle(accent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if store.overrides.hasLessonTypeOverride(for: lesson) {
                Label("detail.type.manual", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("detail.section.type")
        } footer: {
            Text("detail.type.footer")
        }
    }

    private var noteSection: some View {
        Section {
            TextField(
                "note.placeholder",
                text: $noteText,
                axis: .vertical
            )
            .lineLimit(3...8)
        } header: {
            Text("detail.section.note")
        } footer: {
            Text("detail.note.footer")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                toggleMute()
            } label: {
                Label(
                    isMuted ? "detail.unmute" : "detail.mute",
                    systemImage: isMuted ? "bell.badge" : "bell.slash"
                )
            }

            Button(role: .destructive) {
                hideSubject()
            } label: {
                Label("detail.hideSubject", systemImage: "eye.slash")
            }
        } footer: {
            Text("detail.hideSubject.footer")
        }
    }

    // MARK: - Действия

    private var formattedDay: String {
        guard let date = lesson.day.date() else { return lesson.day.description }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var isMuted: Bool {
        let key = UserOverrides.lessonKey(day: lesson.day, bell: lesson.bell, subject: lesson.subject)
        return store.overrides.mutedLessons.contains(key)
    }

    private func setType(_ newType: LessonType?) {
        var updated = store.overrides
        updated.setLessonType(newType, for: lesson)
        store.overrides = updated
    }

    private func toggleMute() {
        var updated = store.overrides
        let key = UserOverrides.lessonKey(day: lesson.day, bell: lesson.bell, subject: lesson.subject)
        if updated.mutedLessons.contains(key) {
            updated.mutedLessons.remove(key)
        } else {
            updated.mutedLessons.insert(key)
        }
        store.overrides = updated
    }

    private func hideSubject() {
        var updated = store.overrides
        updated.hiddenSubjects.insert(UserOverrides.subjectKey(lesson.subject))
        store.overrides = updated
    }

    private func loadNote() {
        guard !didLoadNote else { return }
        noteText = store.text(forLesson: lesson)
        didLoadNote = true
    }

    /// Сохранение при уходе с экрана.
    ///
    /// Отдельной кнопки «Сохранить» нет намеренно: заметка — это не транзакция,
    /// и заставлять пользователя подтверждать каждую правку бессмысленно.
    private func saveNote() {
        guard didLoadNote else { return }
        guard noteText != store.text(forLesson: lesson) else { return }
        store.setNote(noteText, forLesson: lesson)
    }
}