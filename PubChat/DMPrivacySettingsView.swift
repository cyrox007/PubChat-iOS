import SwiftUI

/// Opt-in controls for initiating new direct messages. No local authorization:
/// the backend still checks relationship, blocks and active restrictions.
struct DMPrivacySettingsView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var selectedPolicy: DMConsentPolicy = .nobody
    @State private var serverPolicy: DMConsentPolicy?
    @State private var loading = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var saved = false

    private var primaryPersonaSelected: Bool {
        session.identity?.persona?.isPrimary == true
    }

    var body: some View {
        Form {
            Section {
                Text("Вы решаете, кто может начать личный разговор. Это не отключает блокировки, санкции и другие серверные правила безопасности.")
                    .foregroundStyle(.secondary)
            }

            if !primaryPersonaSelected {
                Section("Основной образ") {
                    Label(
                        "Политика личных сообщений общая для аккаунта. Переключитесь на основную Persona, чтобы изменить её.",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Section("Новые личные сообщения") {
                    if loading {
                        ProgressView("Получаем настройку с сервера…")
                    } else if let currentPolicy = serverPolicy {
                        Picker("Кто может написать", selection: $selectedPolicy) {
                            ForEach(DMConsentPolicy.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .accessibilityIdentifier("dm-consent-policy")

                        Text(selectedPolicy.explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button(saving ? "Сохраняем…" : "Сохранить") {
                            Task { await save() }
                        }
                        .disabled(saving || selectedPolicy == currentPolicy)
                        .accessibilityIdentifier("dm-consent-save")

                        if saving {
                            ProgressView("Проверяем ответ сервера…")
                        } else if saved {
                            Label("Настройка сохранена", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button("Загрузить настройку") {
                            Task { await reload() }
                        }
                    }
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("dm-consent-error")
                    if primaryPersonaSelected {
                        Button("Повторить") { Task { await reload() } }
                            .disabled(loading || saving)
                    }
                }
            }
        }
        .navigationTitle("Приватность чатов")
        .task(id: session.identity?.persona?.uid) {
            if primaryPersonaSelected { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        guard !loading, !saving, primaryPersonaSelected else { return }
        loading = true
        errorText = nil
        serverPolicy = nil
        saved = false
        defer { loading = false }
        do {
            let privacy = try await session.fetchDMPrivacy()
            serverPolicy = privacy.dmPolicy
            selectedPolicy = privacy.dmPolicy
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard !saving, !loading, primaryPersonaSelected,
              let currentPolicy = serverPolicy,
              selectedPolicy != currentPolicy else { return }
        saving = true
        saved = false
        errorText = nil
        defer { saving = false }
        do {
            let privacy = try await session.saveDMPrivacy(selectedPolicy)
            serverPolicy = privacy.dmPolicy
            selectedPolicy = privacy.dmPolicy
            saved = true
        } catch {
            // Retain the server-confirmed value as the baseline; an HTTP error
            // must never masquerade as successfully changed consent.
            errorText = error.localizedDescription
        }
    }
}
