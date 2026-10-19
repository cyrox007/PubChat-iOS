import SwiftUI

/// Real Spaces REST actions. The server enforces space.create and owner-only PATCH.
/// No fake room navigation: the current iOS client is still catalog-oriented.
struct SpaceCategoryEditorView: View {
    @EnvironmentObject private var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    let space: Space?
    @State private var name: String
    @State private var descriptionText: String
    @State private var selected: Set<String>
    @State private var saving = false
    @State private var error: String?
    @State private var success: String?

    private let api = PubChatAPI()

    init(space: Space? = nil) {
        self.space = space
        _name = State(initialValue: space?.name ?? "")
        _descriptionText = State(initialValue: space?.description ?? "")
        _selected = State(initialValue: Set(space?.categorySlugs ?? []))
    }

    private var isEditing: Bool { space != nil }

    private var archivedSelections: [String] {
        let active = Set(session.spaceCategories.map(\.slug))
        return selected.filter { !active.contains($0) }.sorted()
    }

    private var canSave: Bool {
        !saving && session.spaceCategoryError == nil && !session.spaceCategories.isEmpty &&
        archivedSelections.isEmpty && SpaceCategoryValidation.valid(Array(selected)) &&
        (isEditing || (3...80).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)) &&
        descriptionText.count <= 500
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section("Основная информация") {
                        TextField("Название (3–80 символов)", text: $name)
                            .textInputAutocapitalization(.sentences)
                        TextField("Описание (необязательно)", text: $descriptionText, axis: .vertical)
                            .lineLimit(2...4)
                        Text("По умолчанию создаётся публичное пространство со свободным вступлением.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let space {
                    Section("Пространство") {
                        LabeledContent("Название", value: space.name)
                        Text("Изменяются только категории. Название, формат и теги останутся прежними.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if let categoryError = session.spaceCategoryError {
                        Text(categoryError).foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                        Button("Повторить загрузку") {
                            Task { await session.loadSpaceCategories() }
                        }
                    } else if session.spaceCategories.isEmpty {
                        ProgressView("Загружаем категории…")
                    } else {
                        ForEach(session.spaceCategories) { category in
                            Toggle(isOn: Binding(
                                get: { selected.contains(category.slug) },
                                set: { isOn in
                                    if isOn {
                                        if selected.count < 3 { selected.insert(category.slug) }
                                    } else {
                                        selected.remove(category.slug)
                                    }
                                }
                            )) {
                                Label(category.name, systemImage: "number")
                            }
                            .disabled(saving || (!selected.contains(category.slug) && selected.count >= 3))
                        }
                        Text("Можно выбрать не более трёх категорий.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Категории")
                } footer: {
                    Text("Категории администрируются на сервере. Старым пространствам они не присваиваются автоматически.")
                }

                if !archivedSelections.isEmpty {
                    Section("Архивные назначения") {
                        Text("Архивные категории необходимо убрать перед сохранением.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(archivedSelections, id: \.self) { slug in
                            Button("Убрать \(slug)") { selected.remove(slug) }
                                .disabled(saving)
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if let success {
                    Section {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView() }
                            else { Text(isEditing ? "Сохранить категории" : "Создать пространство").bold() }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(!canSave)
                }
            }
            .navigationTitle(isEditing ? "Категории" : "Новое пространство")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                        .disabled(saving)
                }
            }
        }
        .task {
            if session.spaceCategories.isEmpty { await session.loadSpaceCategories() }
        }
    }

    private func save() async {
        guard canSave, let token = SecureStore.accessToken else { return }
        // Only server-derived category slugs are sent. The server validates active
        // assignments and space ownership; these checks are not client authority.
        let slugs = selected.sorted()
        saving = true
        error = nil
        defer { saving = false }
        do {
            if let space {
                _ = try await api.updateSpaceCategories(
                    spaceUID: space.uid, categorySlugs: slugs, accessToken: token
                )
                success = "Категории сохранены"
            } else {
                _ = try await api.createSpace(
                    name: name, description: descriptionText, categorySlugs: slugs, accessToken: token
                )
                success = "Пространство создано"
                // New public Spaces may not match a previously active filter.
                await session.selectSpaceCategory(nil)
            }
            await session.reloadDirectory()
            dismiss()
        } catch {
            error = error.localizedDescription
        }
    }
}
