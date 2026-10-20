import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionViewModel

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                PubChatLoadingView()
            case .signedOut:
                AuthenticationView()
            case .signedIn:
                MainTabsView()
            }
        }
        .tint(PubChatDesign.primary)
        .background(PubChatDesign.background.ignoresSafeArea())
    }
}

private struct AuthenticationView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var registering = false
    @State private var identifier = ""
    @State private var handle = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var intent = "open"

    private let intents = [
        ("open", "Открыт к общению"),
        ("meet", "Знакомства"),
        ("friends", "Друзья"),
        ("games", "Игры"),
        ("quiet", "Спокойное общение")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Text("P")
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(PubChatDesign.brandGradient, in: RoundedRectangle(cornerRadius: 19))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PubChat").font(.system(size: 30, weight: .bold, design: .rounded))
                                Text("Больше, чем чат.").font(.subheadline)
                                    .foregroundStyle(PubChatDesign.secondaryInk)
                            }
                        }
                        Text("Люди. Сообщества. Возможности.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Picker("Действие", selection: $registering) {
                        Text("Вход").tag(false)
                        Text("Регистрация").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section(registering ? "Создать Persona" : "Войти в PubChat") {
                    if registering {
                        TextField("Handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Отображаемое имя", text: $displayName)
                        TextField("Email (необязательно)", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        Picker("Цель общения", selection: $intent) {
                            ForEach(intents.indices, id: \.self) { index in
                                Text(intents[index].1).tag(intents[index].0)
                            }
                        }
                    } else {
                        TextField("Handle или email", text: $identifier)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SecureField("Пароль", text: $password)
                        .textContentType(registering ? .newPassword : .password)
                }

                if let error = session.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task {
                            if registering {
                                await session.signUp(
                                    handle: handle,
                                    displayName: displayName.isEmpty ? handle : displayName,
                                    email: email,
                                    password: password,
                                    intent: intent
                                )
                            } else {
                                await session.signIn(identifier: identifier, password: password)
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Text(registering ? "Создать аккаунт" : "Войти").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        session.isBusy ||
                        password.isEmpty ||
                        (registering ? handle.trimmingCharacters(in: .whitespaces).count < 3 : identifier.isEmpty)
                    )
                }
            }
            .navigationTitle("Добро пожаловать")
        }
    }
}

private struct MainTabsView: View {
    @EnvironmentObject private var session: SessionViewModel
    @State private var selectedTab = 0
    @State private var showCreateSpace = false
    @State private var editingSpace: Space?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(PubChatDesign.primary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Открывай своё").font(.title2.bold())
                                Text("Сообщества и разговоры по интересам")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        HStack(spacing: 10) {
                            Menu {
                                Button("Все категории") {
                                    Task { await session.selectSpaceCategory(nil) }
                                }
                                ForEach(session.spaceCategories) { item in
                                    Button(item.name) {
                                        Task { await session.selectSpaceCategory(item.slug) }
                                    }
                                }
                            } label: {
                                Label(
                                    session.selectedSpaceCategory.map(session.spaceCategoryName) ?? "Все категории",
                                    systemImage: "line.3.horizontal.decrease.circle"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PubChatDesign.primary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(PubChatDesign.surface,
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                            .accessibilityLabel("Выбрать категорию пространства")
                            .disabled(session.isLoadingDirectory || session.spaceCategories.isEmpty)
                            Spacer(minLength: 0)
                            if session.selectedSpaceCategory != nil {
                                Button("Сбросить") {
                                    Task { await session.selectSpaceCategory(nil) }
                                }
                                .font(.caption.weight(.semibold))
                                .disabled(session.isLoadingDirectory)
                            }
                        }
                        .padding(.horizontal, 18)
                        if let categoryError = session.spaceCategoryError {
                            HStack {
                                Text(categoryError).font(.caption)
                                Button("Повторить") { Task { await session.loadSpaceCategories() } }
                            }
                            .foregroundStyle(PubChatDesign.secondaryInk)
                            .padding(.horizontal, 20)
                        }
                        if !session.spaces.isEmpty {
                            Text("В каталоге: \(session.spaces.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PubChatDesign.primary)
                                .padding(.horizontal, 20)
                                .accessibilityLabel("Пространств в каталоге: \(session.spaces.count)")
                        }

                        if session.isLoadingDirectory && session.spaces.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(PubChatDesign.primary.opacity(0.07))
                                    .frame(height: 118)
                                    .overlay(alignment: .leading) {
                                        HStack(spacing: 14) {
                                            Circle().fill(PubChatDesign.primary.opacity(0.09))
                                                .frame(width: 58, height: 58)
                                            VStack(alignment: .leading, spacing: 12) {
                                                Capsule().fill(PubChatDesign.primary.opacity(0.1))
                                                    .frame(width: 158, height: 16)
                                                Capsule().fill(PubChatDesign.primary.opacity(0.07))
                                                    .frame(width: 200, height: 12)
                                            }
                                        }.padding(18)
                                    }
                                    .accessibilityLabel("Загрузка пространства")
                            }
                            .padding(.horizontal, 16)
                        } else if session.spaces.isEmpty {
                            PubChatStateCard(
                                symbol: session.directoryError == nil ? "square.grid.2x2" : "wifi.exclamationmark",
                                title: session.directoryError == nil ? "Пока нет пространств" : "Не удалось загрузить",
                                message: session.directoryError == nil
                                    ? "Попробуйте обновить каталог или открыть раздел «Люди»."
                                    : "Проверьте подключение и повторите попытку.",
                                actionTitle: "Обновить",
                                action: { Task { await session.reloadDirectory() } }
                            )
                            .padding(.horizontal, 16)
                        } else {
                            if let directoryError = session.directoryError {
                                PubChatStateCard(
                                    symbol: "wifi.exclamationmark",
                                    title: "Не удалось обновить каталог",
                                    message: "Показаны последние загруженные пространства. \(directoryError)",
                                    actionTitle: "Повторить",
                                    action: { Task { await session.reloadDirectory() } }
                                )
                                .padding(.horizontal, 16)
                            }
                            ForEach(session.spaces) { space in
                                SpaceDirectoryCard(
                                    space: space,
                                    categoryNames: (space.categorySlugs ?? []).map(session.spaceCategoryName),
                                    onEdit: space.owned(by: session.identity?.account?.uid)
                                        ? { editingSpace = space } : nil
                                )
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .background(PubChatDesign.background)
                .refreshable { await session.reloadDirectory() }
                .navigationTitle("Пространства")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showCreateSpace = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Создать пространство")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await session.reloadDirectory() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Обновить каталог пространств")
                        .disabled(session.isLoadingDirectory)
                    }
                }
            }
            .tabItem { Label("Пространства", systemImage: "square.grid.2x2.fill") }
            .tag(0)

            NavigationStack {
                SocialDiscoveryView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                FriendshipHubView()
                            } label: {
                                Label("Друзья и заявки", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        }
                    }
            }
            .tabItem { Label("Люди", systemImage: "person.2.fill") }
            .tag(1)

            MessengerHubView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(2)

            NavigationStack {
                NotificationCenterView()
            }
            .tabItem { Label("Активность", systemImage: "bell.fill") }
            .tag(3)

            NavigationStack {
                Form {
                    if let persona = session.identity?.persona {
                        Section("Моя Persona") {
                            LabeledContent("Имя", value: persona.displayName)
                            LabeledContent("Handle", value: "@\(persona.handle)")
                            if let bio = persona.bio, !bio.isEmpty {
                                Text(bio)
                            }
                        }
                    }
                    Section("Persona") {
                        NavigationLink("Мои образы") { PersonaManagerView() }
                    }
                    Section("Приватность") {
                        NavigationLink {
                            DMPrivacySettingsView()
                        } label: {
                            Label("Кто может написать мне", systemImage: "hand.raised")
                        }
                    }
                    Section {
                        Text("Это развивающийся iOS-клиент. Некоторые функции Spaces, игр и безопасности пока доступны только в других клиентах.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Выйти из аккаунта", role: .destructive) {
                            Task { await session.signOut() }
                        }
                        .disabled(session.isBusy)
                    }
                }
                .navigationTitle("Профиль")
            }
            .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
            .tag(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pubChatPushOpened)) { signal in
            let type = signal.userInfo?["type"] as? String
            if type == "messenger" { selectedTab = 2 }
            if type == "space_reply" { selectedTab = 0 }
        }
        .task {
            await session.loadSpaceCategories()
            await session.reloadDirectory()
        }
        .sheet(isPresented: $showCreateSpace) {
            SpaceCategoryEditorView()
                .environmentObject(session)
        }
        .sheet(item: $editingSpace) { space in
            SpaceCategoryEditorView(space: space)
                .environmentObject(session)
        }
        .overlay(alignment: .top) {
            if session.isLoadingDirectory {
                HStack(spacing: 10) {
                    ProgressView().tint(PubChatDesign.primary)
                    Text("Обновляем…").font(.caption)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 6)
            }
        }
    }
}

private struct SpaceDirectoryCard: View {
    let space: Space
    let categoryNames: [String]
    let onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(PubChatDesign.brandGradient,
                            in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(space.name)
                    .font(.headline)
                    .foregroundStyle(PubChatDesign.ink)
                if !categoryNames.isEmpty {
                    Text(categoryNames.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PubChatDesign.primary)
                        .lineLimit(2)
                } else {
                    Text("Пространство для общения")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PubChatDesign.primary)
                }
                if let description = space.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(PubChatDesign.secondaryInk)
                        .lineLimit(3)
                }
                if let onEdit {
                    Button("Изменить категории", action: onEdit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PubChatDesign.primary)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PubChatDesign.surface,
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(PubChatDesign.border, lineWidth: 1))
        // iOS currently has a catalog-only Spaces API. No inert join button.
        .accessibilityElement(children: .contain)
    }
}
