import SwiftUI

/// Native, consent-first discovery. Server filtering enforces privacy and
/// Account blocks; no client-side cache exposes hidden Persona fields.
struct SocialDiscoveryView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var query = ""
    @State private var intent = "all"
    @State private var availableNow = false
    @State private var people: [Person] = []
    @State private var total = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var errorText: String?
    @State private var generation = 0
    @State private var availability: SocialAvailability?
    @State private var editingAvailability = false

    private let intents: [(String, String)] = [
        ("all", "Все"),
        ("open", "Общение"),
        ("meet", "Знакомства"),
        ("friends", "Друзья"),
        ("games", "Игры"),
        ("quiet", "Спокойно")
    ]

    var body: some View {
        List {
            Section("Открыт к общению") {
                if let availability {
                    Label("Сейчас: \(intentName(availability.intent))", systemImage: "bolt.fill")
                    if let note = availability.note, !note.isEmpty { Text(note) }
                    Text("Истекает автоматически: \(availability.expiresAt)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Временный статус помогает найти компанию. Выключается автоматически.")
                        .foregroundStyle(.secondary)
                }
                Button(availability == nil ? "Включить статус" : "Изменить статус") {
                    editingAvailability = true
                }
            }

            Section("Фильтры поиска") {
                Picker("Намерение", selection: $intent) {
                    ForEach(intents.indices, id: \.self) { index in
                        Text(intents[index].1).tag(intents[index].0)
                    }
                }
                Toggle("Открыты сейчас", isOn: $availableNow)
                Button("Применить фильтры") { Task { await load() } }
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
                Section { Button("Повторить") { Task { await load() } } }
            }
            if loading {
                Section { ProgressView("Ищем людей…") }
            } else if people.isEmpty && errorText == nil {
                Section {
                    ContentUnavailableView("Люди не найдены", systemImage: "person.2")
                }
            }

            ForEach(people) { person in
                NavigationLink {
                    PersonDetailView(person: person)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(person.displayName).font(.headline)
                        if let handle = person.handle { Text("@\(handle)").font(.caption).foregroundStyle(.secondary) }
                        if let status = person.availability {
                            Label(intentName(status.intent), systemImage: "bolt.fill")
                                .font(.caption).foregroundStyle(.green)
                            if let note = status.note, !note.isEmpty { Text(note).font(.subheadline) }
                        } else if let intent = person.socialIntent {
                            Text(intentName(intent)).font(.caption).foregroundStyle(.secondary)
                        }
                        if let bio = person.bio, !bio.isEmpty { Text(bio).lineLimit(2) }
                    }.padding(.vertical, 4)
                }
            }
            if people.count < total {
                Section {
                    Button(loadingMore ? "Загружаем…" : "Показать ещё") {
                        Task { await load(append: true) }
                    }.disabled(loading || loadingMore)
                }
            }
        }
        .searchable(text: $query, prompt: "Имя, @handle или интересы")
        .onSubmit(of: .search) { Task { await load() } }
        .navigationTitle("Люди")
        .refreshable { await load() }
        .task {
            await loadAvailability()
            await load()
        }
        .sheet(isPresented: $editingAvailability) {
            SocialAvailabilityEditor(availability: availability) { intent, duration, note in
                let updated = try await session.saveSocialAvailability(
                    intent: intent, duration: duration, note: note
                )
                availability = updated
                await load()
            } onClear: {
                try await session.endSocialAvailability()
                availability = nil
                await load()
            }
        }
    }

    @MainActor private func loadAvailability() async {
        do { availability = try await session.getSocialAvailability() }
        catch { errorText = error.localizedDescription }
    }

    @MainActor private func load(append: Bool = false) async {
        if append && (loading || loadingMore) { return }
        generation += 1
        let current = generation
        if append { loadingMore = true }
        else { loading = true; errorText = nil }
        defer {
            if current == generation { loading = false; loadingMore = false }
        }
        do {
            let page = try await session.discoverPeople(
                query: query, intent: intent == "all" ? nil : intent,
                availableNow: availableNow, offset: append ? people.count : 0
            )
            guard current == generation else { return }
            if append {
                let known = Set(people.map(\.id))
                people += page.people.filter { !known.contains($0.id) }
            } else {
                people = page.people
            }
            total = page.pagination.total
        } catch {
            if current == generation { errorText = error.localizedDescription }
        }
    }

    private func intentName(_ value: String) -> String {
        switch value {
        case "open": return "Хочет пообщаться"
        case "meet": return "Открыт к знакомствам"
        case "friends": return "Ищет друзей"
        case "games": return "Ищет компанию для игры"
        case "quiet": return "Спокойный разговор"
        default: return "Общение"
        }
    }
}

private struct SocialAvailabilityEditor: View {
    @Environment(\.dismiss) private var dismiss
    let availability: SocialAvailability?
    let onSave: (String, Int, String) async throws -> Void
    let onClear: () async throws -> Void
    @State private var intent = "open"
    @State private var duration = 120
    @State private var note = ""
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Я хочу", selection: $intent) {
                    Text("Пообщаться").tag("open")
                    Text("Познакомиться").tag("meet")
                    Text("Найти игру").tag("games")
                }
                Picker("Время", selection: $duration) {
                    Text("30 минут").tag(30)
                    Text("2 часа").tag(120)
                    Text("8 часов").tag(480)
                }
                TextField("О чём хочется поговорить", text: $note)
                    .onChange(of: note) { _, value in if value.count > 120 { note = String(value.prefix(120)) } }
                if let errorText { Text(errorText).foregroundStyle(.red) }
                Button(saving ? "Сохраняем…" : "Сохранить статус") {
                    Task { await perform { try await onSave(intent, duration, note) } }
                }.disabled(saving)
                if availability != nil {
                    Button("Завершить статус", role: .destructive) {
                        Task { await perform { try await onClear() } }
                    }.disabled(saving)
                }
            }
            .navigationTitle("Открыт сейчас")
            .toolbar { Button("Закрыть") { dismiss() } }
            .onAppear {
                if let availability {
                    intent = availability.intent
                    note = availability.note ?? ""
                }
            }
        }
    }

    @MainActor private func perform(_ operation: () async throws -> Void) async {
        guard !saving else { return }
        saving = true
        errorText = nil
        defer { saving = false }
        do { try await operation(); dismiss() }
        catch { errorText = error.localizedDescription }
    }
}
