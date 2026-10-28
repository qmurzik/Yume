import Foundation

/// Signs in to YummyAnime and gets the app's public key through the official API:
/// `POST /profile/login` → user token → `GET /apps` (or `POST /apps`) → `GET /apps/{id}` → `public_token`.
/// The password is sent only to YummyAnime and never stored; the user token isn't kept either.
struct YummyAccountService: Sendable {
    var baseURL = AppConfig.yummyBaseURL
    static let appName = "AnimeApp (iOS)"

    private func client(userToken: String? = nil, appToken: String? = nil) -> HTTPClient {
        var headers = ["Lang": "ru", "Accept": "application/json"]
        if let userToken { headers["Authorization"] = "Bearer \(userToken)" }
        if let appToken { headers["X-Application"] = appToken }
        return HTTPClient(defaultHeaders: headers)
    }

    private struct Envelope<T: Decodable>: Decodable {
        let response: T?
    }

    private struct LoginBody: Encodable {
        let login: String
        let password: String
        let need_json: Bool
    }

    private struct LoginResult: Decodable {
        let success: Bool?
        let token: String?
    }

    private struct Profile: Decodable {
        let id: Int?
        let nickname: String?
    }

    private struct AppSummary: Decodable {
        struct Owner: Decodable { let id: Int? }
        let appId: Int
        let name: String?
        let owner: Owner?
    }

    private struct AppDetails: Decodable {
        let publicToken: String?
    }

    private struct CreatedApp: Decodable {
        let appId: Int
    }

    private struct NewApp: Encodable {
        let name: String
        let description: String
    }

    struct Result: Sendable {
        let appToken: String
        let nickname: String?
    }

    /// Full flow: sign in, find or create this app, return its public key.
    func signIn(login: String, password: String) async throws -> Result {
        let userToken = try await self.userToken(login: login, password: password)
        let profile = try? await self.profile(userToken: userToken)
        let token = try await appToken(userToken: userToken, ownerID: profile?.id)
        return Result(appToken: token, nickname: profile?.nickname ?? login)
    }

    func userToken(login: String, password: String) async throws -> String {
        let data: Data
        do {
            data = try await client().postJSON(baseURL.appendingPathComponent("profile/login"),
                                               body: LoginBody(login: login, password: password, need_json: true))
        } catch APIError.http(let status) {
            switch status {
            case 420:
                throw APIError.server("YummyAnime просит пройти капчу. Войдите на сайте yummyani.me и вставьте ключ приложения вручную.")
            case 400, 401, 403, 404:
                throw APIError.server("Неверный логин или пароль.")
            default:
                throw APIError.http(status: status)
            }
        } catch APIError.notFound {
            throw APIError.server("Неверный логин или пароль.")
        }
        guard let token = try JSONDecoder.api.decodeAPI(Envelope<LoginResult>.self, from: data).response?.token, !token.isEmpty else {
            throw APIError.server("Неверный логин или пароль.")
        }
        return token
    }

    private func profile(userToken: String) async throws -> Profile? {
        let data = try await client(userToken: userToken).get(baseURL.appendingPathComponent("profile"))
        return try JSONDecoder.api.decodeAPI(Envelope<Profile>.self, from: data).response
    }

    private func appToken(userToken: String, ownerID: Int?) async throws -> String {
        let http = client(userToken: userToken)
        let listData = try await http.get(baseURL.appendingPathComponent("apps"), query: [URLQueryItem(name: "limit", value: "100")])
        let apps = try JSONDecoder.api.decodeAPI(Envelope<[AppSummary]>.self, from: listData).response ?? []
        let mine = apps.first { $0.name == Self.appName && (ownerID == nil || $0.owner?.id == nil || $0.owner?.id == ownerID) }

        let appID: Int
        if let mine {
            appID = mine.appId
        } else {
            let created = try await http.postJSON(baseURL.appendingPathComponent("apps"),
                                                  body: NewApp(name: Self.appName, description: "Личное приложение для просмотра аниме на iPhone"))
            guard let id = try JSONDecoder.api.decodeAPI(Envelope<CreatedApp>.self, from: created).response?.appId else {
                throw APIError.server("YummyAnime не создал приложение. Создайте его на сайте и вставьте ключ вручную.")
            }
            appID = id
        }

        let details = try await http.get(baseURL.appendingPathComponent("apps/\(appID)"))
        guard let token = try JSONDecoder.api.decodeAPI(Envelope<AppDetails>.self, from: details).response?.publicToken, !token.isEmpty else {
            throw APIError.server("YummyAnime не вернул ключ приложения.")
        }
        return token
    }

    /// Checks a pasted key with a cheap request.
    func validate(appToken: String) async throws {
        do {
            _ = try await client(appToken: appToken).get(baseURL.appendingPathComponent("anime"), query: [URLQueryItem(name: "limit", value: "1")])
        } catch APIError.http(let status) where status == 401 || status == 403 {
            throw APIError.server("YummyAnime не принял этот ключ. Проверьте, что скопирован публичный токен приложения.")
        }
    }
}
