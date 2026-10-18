import SwiftUI

/// Relationship actions are always authorized by the backend Account, while
/// the public UI displays only the other person's Persona.
struct PersonDetailView: View {
    let person: Person

    @EnvironmentObject private var session: SessionViewModel
    @State private var relationship: Relationship?
    @State private var loading = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var askToBlock = false

    var body: some View {
        Form {
            Section("Persona") {
                Text(person.displayName).font(.title2.bold())
                if let handle = person.handle {
                    Text("@\(handle)").foregroundStyle(.secondary)
                }
                if let bio = person.bio, !bio.isEmpty { Text(bio) }
                if let intent = person.socialIntent {
                    LabeledContent("Настроение", value: intentLabel(intent))
                }
            }

            Section("Социальные связи") {
                if loading {
                    ProgressView("Загружаем отношения…")
                } else if let relation = relationship {
                    if relation.blockedByMe {
                        Text("Вы заблокировали этот аккаунт. Подписки и дружба недоступны.")
                            .foregroundStyle(.secondary)
                        Button("Разблокировать", role: .destructive) {
                            Task { await update { try await session.toggleBlock(
                                accountUid: person.accountUid, currentlyBlocked: true
                            ) } }
                        }
                        .disabled(saving)
                    } else if relation.blockedMe {
                        Text("Социальные действия недоступны из-за настроек доступа.")
                            .foregroundStyle(.secondary)
                    } else {
                        if relation.friends {
                            Label("Вы друзья", systemImage: "person.2.fill")
                                .foregroundStyle(.secondary)
                        }
                        if relation.followedBy {
                            Label("Подписан(а) на вас", systemImage: "person.crop.circle.badge.checkmark")
                                .foregroundStyle(.secondary)
                        }
                        if relation.friendRequest == "incoming" {
                            Text("Этот человек предложил дружбу.")
                                .foregroundStyle(.secondary)
                        } else if relation.friendRequest == "outgoing" {
                            Text("Запрос на дружбу ожидает ответа.")
                                .foregroundStyle(.secondary)
                        }

                        Button(relation.following ? "Отписаться" : "Подписаться") {
                            Task { await update { try await session.toggleFollow(
                                accountUid: person.accountUid, currentlyFollowing: relation.following
                            ) } }
                        }
                        .disabled(saving)

                        Button(relation.friendActionTitle) {
                            Task { await update { try await session.friendAction(
                                accountUid: person.accountUid, action: relation.friendAction
                            ) } }
                        }
                        .disabled(saving)

                        if relation.friendRequest == "incoming" {
                            Button("Отклонить запрос") {
                                Task { await update { try await session.friendAction(
                                    accountUid: person.accountUid, action: "reject"
                                ) } }
                            }
                            .disabled(saving)
                        }

                        Button("Заблокировать", role: .destructive) { askToBlock = true }
                            .disabled(saving)
                    }
                    if saving { ProgressView("Обновляем…") }
                } else {
                    Button("Повторить загрузку") { Task { await reload() } }
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                        .accessibilityIdentifier("relationship-error")
                }
            }
        }
        .navigationTitle("Профиль")
        .task(id: person.accountUid) { await reload() }
        .confirmationDialog(
            "Заблокировать этот аккаунт?",
            isPresented: $askToBlock,
            titleVisibility: .visible
        ) {
            Button("Заблокировать", role: .destructive) {
                Task { await update { try await session.toggleBlock(
                    accountUid: person.accountUid, currentlyBlocked: false
                ) } }
            }
        } message: {
            Text("После блокировки общение и социальные действия станут недоступны.")
        }
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            relationship = try await session.relationship(accountUid: person.accountUid)
        } catch {
            relationship = nil
            errorText = error.localizedDescription
        }
    }

    private func update(_ operation: () async throws -> Relationship) async {
        guard !saving, !loading else { return }
        saving = true
        errorText = nil
        defer { saving = false }
        do {
            // Trust the returned server projection, not an optimistic local mutation.
            relationship = try await operation()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func intentLabel(_ value: String) -> String {
        switch value {
        case "open": return "Открыт(а) к общению"
        case "meet": return "Новые знакомства"
        case "friends": return "Друзья"
        case "games": return "Совместные игры"
        case "quiet": return "Спокойный разговор"
        default: return "Общение"
        }
    }
}
