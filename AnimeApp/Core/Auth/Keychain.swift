import Foundation
#if canImport(Security)
import Security
#endif

/// Small generic-password Keychain wrapper (in-memory where Security isn't available).
enum Keychain {
    private static let service = "com.qmurzik.animeapp"

    #if canImport(Security)
    static func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
    #else
    private static var memory: [String: String] = [:]
    static func string(for key: String) -> String? { memory[key] }
    static func set(_ value: String?, for key: String) { memory[key] = value }
    #endif
}

/// YummyAnime application key: from the build config, or obtained in the app by signing in
/// (or pasted by hand) and kept in the Keychain.
final class YummyCredentials: @unchecked Sendable {
    static let shared = YummyCredentials()
    static let didChange = Notification.Name("YummyCredentialsDidChange")

    private let lock = NSLock()
    private var loaded = false
    private var storedToken: String?
    private var storedNickname: String?

    private static let tokenKey = "yummy.appToken"
    private static let nicknameKey = "yummy.nickname"

    private func load() {
        guard !loaded else { return }
        storedToken = Keychain.string(for: Self.tokenKey)
        storedNickname = Keychain.string(for: Self.nicknameKey)
        loaded = true
    }

    /// Key used for requests: the build's key wins, otherwise the one saved in the app.
    var appToken: String? {
        lock.lock(); defer { lock.unlock() }
        load()
        return AppConfig.yummyAppToken ?? storedToken
    }

    var isFromBuild: Bool { AppConfig.yummyAppToken != nil }

    /// Account the key was obtained with, when it came from signing in.
    var nickname: String? {
        lock.lock(); defer { lock.unlock() }
        load()
        return storedNickname
    }

    var hasSavedToken: Bool {
        lock.lock(); defer { lock.unlock() }
        load()
        return storedToken != nil
    }

    func save(token: String, nickname: String?) {
        lock.lock()
        storedToken = token
        storedNickname = nickname
        loaded = true
        lock.unlock()
        Keychain.set(token, for: Self.tokenKey)
        Keychain.set(nickname, for: Self.nicknameKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func clear() {
        lock.lock()
        storedToken = nil
        storedNickname = nil
        loaded = true
        lock.unlock()
        Keychain.set(nil, for: Self.tokenKey)
        Keychain.set(nil, for: Self.nicknameKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
