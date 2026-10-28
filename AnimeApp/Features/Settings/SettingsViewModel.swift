import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var login = ""
    @Published var password = ""
    @Published var manualToken = ""
    @Published private(set) var isWorking = false
    @Published private(set) var error: String?
    @Published private(set) var nickname: String?
    @Published private(set) var isConnected = false
    @Published private(set) var isFromBuild = false

    private let credentials: YummyCredentials
    private let service: YummyAccountService
    private var observer: NSObjectProtocol?

    init(credentials: YummyCredentials = .shared, service: YummyAccountService = YummyAccountService()) {
        self.credentials = credentials
        self.service = service
        refresh()
        observer = NotificationCenter.default.addObserver(forName: YummyCredentials.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var canSignIn: Bool {
        !login.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isWorking
    }

    private func refresh() {
        isConnected = credentials.appToken != nil
        isFromBuild = credentials.isFromBuild
        nickname = credentials.nickname
    }

    func signIn() async {
        guard canSignIn else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let result = try await service.signIn(login: login.trimmingCharacters(in: .whitespaces), password: password)
            credentials.save(token: result.appToken, nickname: result.nickname)
            password = ""
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveManualToken() async {
        let token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await service.validate(appToken: token)
            credentials.save(token: token, nickname: nil)
            manualToken = ""
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() {
        credentials.clear()
        login = ""
        password = ""
        error = nil
    }
}
