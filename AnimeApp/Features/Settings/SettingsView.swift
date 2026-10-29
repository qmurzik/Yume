import SwiftUI

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?
    @State private var showManual = false
    @State private var showAnime365Login = false
    @State private var anime365Name = Anime365Account.shared.name
    @State private var anime365Premium = Anime365Account.shared.premiumUntil
    @AppStorage("player.autoplayNext") private var autoplay = true
    @AppStorage("player.preferredQuality") private var preferredQuality = 1080

    private enum Field { case login, password, token }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    anime365Card
                    yummyCard
                    sourcesCard
                    playerCard
                    aboutCard
                }
                .padding()
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.isConnected)
                .animation(.easeInOut, value: model.error)
            }
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showAnime365Login) { Anime365LoginView() }
            .onReceive(NotificationCenter.default.publisher(for: Anime365Account.didChange)) { _ in
                anime365Name = Anime365Account.shared.name
                anime365Premium = Anime365Account.shared.premiumUntil
            }
            .screenBackground()
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Anime365

    private var anime365Card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accentFill)
                    Text("365").font(.display(13, .black, relativeTo: .caption)).foregroundStyle(Theme.cream)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anime365").font(.headline)
                    Text(anime365Status)
                        .font(.caption)
                        .foregroundStyle(anime365Name == nil ? Theme.secondaryText : (anime365Premium == nil ? Color.orange : Color.green))
                }
                Spacer()
            }
            Text("Десятки русских озвучек почти для любого тайтла, видео до 1080p играет в нашем плеере. Ссылки на видео Anime365 выдаёт только аккаунтам с активной подпиской на их сайте.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if anime365Name == nil {
                Button {
                    showAnime365Login = true
                } label: {
                    Text("Войти на сайте Anime365").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(role: .destructive) {
                    Anime365Account.shared.signOut()
                } label: {
                    Text("Выйти").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(16)
        .card(radius: 20)
    }

    private var anime365Status: String {
        guard let name = anime365Name else { return "Не подключено" }
        if let until = anime365Premium { return "\(name) · подписка до \(until.prefix(10))" }
        return "\(name) · без подписки, видео не откроется"
    }

    // MARK: YummyAnime

    private var yummyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accentFill)
                    Image(systemName: "person.crop.circle.badge.checkmark").font(.title3.weight(.semibold)).foregroundStyle(Theme.cream)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("YummyAnime").font(.headline)
                    Text(statusText).font(.caption).foregroundStyle(model.isConnected ? Color.green : Theme.secondaryText)
                }
                Spacer()
            }

            if model.isConnected {
                connectedContent
            } else {
                Text("Вход открывает десятки озвучек и субтитров, в том числе для тайтлов, которых нет в AniLibria и AnimeVost. Приложение само создаст в вашем аккаунте ключ приложения, как требует API YummyAnime.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                signInForm
            }

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .card(radius: 20)
    }

    private var statusText: String {
        if model.isFromBuild { return "Подключено ключом из сборки" }
        if model.isConnected { return model.nickname.map { "Подключено · \($0)" } ?? "Подключено ключом" }
        return "Не подключено"
    }

    @ViewBuilder
    private var connectedContent: some View {
        Label("Озвучки YummyAnime появятся в карточках тайтлов.", systemImage: "checkmark.seal.fill")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        if !model.isFromBuild {
            Button(role: .destructive) {
                Haptics.tap()
                model.signOut()
            } label: {
                Text("Выйти и удалить ключ").frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    private var signInForm: some View {
        VStack(spacing: 12) {
            field("Логин или e-mail", text: $model.login, systemImage: "person")
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .focused($focused, equals: .login)
                .submitLabel(.next)
                .onSubmit { focused = .password }
            secureField
            Button {
                focused = nil
                Task { await model.signIn() }
            } label: {
                HStack {
                    if model.isWorking { ProgressView().tint(.white) }
                    Text(model.isWorking ? "Входим…" : "Войти").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canSignIn)
            .opacity(model.canSignIn || model.isWorking ? 1 : 0.5)

            Text("Пароль уходит только на сервер YummyAnime и не сохраняется. На устройстве хранится лишь ключ приложения, в Keychain.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)

            DisclosureGroup(isExpanded: $showManual) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Создайте приложение на yummyani.me/dev/applications и вставьте его публичный токен.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    field("Публичный токен", text: $model.manualToken, systemImage: "key")
                        .focused($focused, equals: .token)
                    Button {
                        focused = nil
                        Task { await model.saveManualToken() }
                    } label: {
                        Text("Сохранить ключ").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(model.manualToken.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
                    Link(destination: URL(string: "https://yummyani.me/dev/applications")!) {
                        Label("Открыть страницу приложений", systemImage: "safari")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Вставить ключ вручную").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream)
            }
            .tint(Theme.accent)
        }
    }

    private func field(_ title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(Theme.tertiaryText).frame(width: 20)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }

    private var secureField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock").foregroundStyle(Theme.tertiaryText).frame(width: 20)
            SecureField("Пароль", text: $model.password)
                .textContentType(.password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await model.signIn() } }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }

    // MARK: Other sections

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Источники видео").font(.headline)
            sourceRow("AniLibria", detail: "Своя озвучка, HLS до 1080p, пропуск опенингов", on: true)
            sourceRow("AnimeVost", detail: "Своя озвучка, MP4 480p и 720p", on: true)
            sourceRow("Anime365", detail: "Десятки озвучек, нужен аккаунт с подпиской", on: anime365Name != nil)
            sourceRow("YummyAnime", detail: "Много озвучек и субтитров, встроенные плееры", on: model.isConnected)
            Text("Если тайтла нет в одном источнике, карточка сама пробует следующий.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(16)
        .card(radius: 20)
    }

    private func sourceRow(_ title: String, detail: String, on: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(on ? Color.green : Theme.tertiaryText).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text(on ? "Вкл." : "Выкл.").font(.caption.weight(.bold)).foregroundStyle(on ? Color.green : Theme.tertiaryText)
        }
    }

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Плеер").font(.headline)
            Toggle(isOn: $autoplay) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Автовоспроизведение").font(.subheadline.weight(.semibold))
                    Text("Включать следующую серию после титров").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)
            VStack(alignment: .leading, spacing: 8) {
                Text("Качество по умолчанию").font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach([1080, 720, 480], id: \.self) { height in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { preferredQuality = height }
                        } label: {
                            Chip(title: "\(height)p", isSelected: preferredQuality == height)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .padding(16)
        .card(radius: 20)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("О приложении").font(.headline)
            Text("Каталог и описания — Shikimori. Видео — AniLibria, AnimeVost и YummyAnime через их официальные API.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 20)
    }
}
