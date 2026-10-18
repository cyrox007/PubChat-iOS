import SwiftUI

/// Uses the Account-level social graph and a public Persona preview from the
/// server. Server responses, not local guesses, authorize friendship changes.
struct FriendshipHubView: View {
    private enum Bucket: String, CaseIterable, Identifiable {
        case incoming, outgoing, friends
        var id: String { rawValue }
        var title: String {
            switch self {
            case .incoming: return "Входящие"
            case .outgoing: return "Исходящие"
            case .friends: return "Друзья"
            }
        }
        var emptyMessage: String {
            switch self {
            case .incoming: return "Пока никто не предложил дружбу."
            case .outgoing: return "Вы ещё не отправляли заявок."
            case .friends: return "Друзья появятся после взаимного согласия."
            }
        }
    }

    @EnvironmentObject private var session: SessionViewModel
    @State private var bucket: Bucket = .incoming
    @State private var rows: [FriendshipRow] = []
    @State private var total = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var busyUid: String?
    @State private var errorText: String?
    @State private var pendingRemove: FriendshipRow?

    var body: some View {
        List {
            Section {
                Picker("Список", selection: $bucket) {
                    ForEach(Bucket.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("friendship-bucket")
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                    Button("Повторить") { Task { await reload() } }
                }
            }

            if loading {
                Section { ProgressView("Загружаем…") }
            } else if rows.isEmpty && errorText == nil {
                Section { ContentUnavailableView(bucket.emptyMessage, systemImage: "person.2") }
            }

            ForEach(rows) { row in
                Section {
                    NavigationLink {
                        PersonDetailView(person: Person(
                            accountUid: row.accountUid,
                            displayName: row.displayName,
                            handle: row.persona?.handle,
                            bio: nil,
                            socialIntent: nil
                        ))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.displayName).font(.headline)
                            if let handle = row.persona?.handle {
                                Text("@\(handle)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        if bucket == .incoming {
                            Button("Принять") { Task { await act(row, "accept") } }
                                .buttonStyle(.borderedProminent)
                            Button("Отклонить") { Task { await act(row, "reject") } }
                                .buttonStyle(.bordered)
                        } else if bucket == .outgoing {
                            Button("Отменить запрос") { Task { await act(row, "remove") } }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Удалить из друзей", role: .destructive) {
                                pendingRemove = row
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .disabled(busyUid != nil)
                    if busyUid == row.id { ProgressView("Сохраняем…") }
                }
            }

            if rows.count < total {
                Section {
                    Button(loadingMore ? "Загружаем…" : "Показать ещё") {
                        Task { await load(append: true) }
                    }
                    .disabled(loading || loadingMore || busyUid != nil)
                }
            }
        }
        .navigationTitle("Друзья и заявки")
        .refreshable { await reload() }
        .task(id: bucket) { await reload() }
        .confirmationDialog(
            "Удалить из друзей?",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let row = pendingRemove {
                Button("Удалить", role: .destructive) {
                    pendingRemove = nil
                    Task { await act(row, "remove") }
                }
            }
        } message: {
            Text("Вы сможете снова предложить дружбу позднее.")
        }
    }

    @MainActor private func reload() async { await load(append: false) }

    @MainActor private func load(append: Bool) async {
        if loading || loadingMore { return }
        if append { loadingMore = true } else { loading = true }
        defer { loading = false; loadingMore = false }
        let selectedBucket = bucket
        if !append { errorText = nil }
        do {
            let offset = append ? rows.count : 0
            let fetched: [FriendshipRow]
            let count: Int
            switch selectedBucket {
            case .incoming, .outgoing:
                let result = try await session.listFriendRequests(
                    direction: selectedBucket.rawValue, offset: offset
                )
                fetched = result.requests
                count = result.pagination.total
            case .friends:
                let result = try await session.listFriends(offset: offset)
                fetched = result.friends
                count = result.pagination.total
            }
            guard bucket == selectedBucket else { return }
            if append {
                let known = Set(rows.map(\.id))
                rows += fetched.filter { !known.contains($0.id) }
            } else {
                rows = fetched
            }
            total = count
        } catch {
            guard bucket == selectedBucket else { return }
            errorText = error.localizedDescription
        }
    }

    @MainActor private func act(_ row: FriendshipRow, _ action: String) async {
        guard busyUid == nil else { return }
        busyUid = row.accountUid
        errorText = nil
        defer { busyUid = nil }
        do {
            _ = try await session.friendAction(accountUid: row.accountUid, action: action)
            // Do not infer the new state: reload the authoritative server list.
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
