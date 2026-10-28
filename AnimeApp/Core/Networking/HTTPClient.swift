import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin async wrapper over URLSession: common headers, optional rate limiting, status checks.
struct HTTPClient: Sendable {
    var session: URLSession = .shared
    var defaultHeaders: [String: String] = [:]
    var rateLimiter: RateLimiter?

    func data(for request: URLRequest) async throws -> Data {
        var request = request
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        for (key, value) in defaultHeaders where request.value(forHTTPHeaderField: key) == nil {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 30

        if let rateLimiter { try await rateLimiter.acquire() }
        try Task.checkCancellation()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return data }
            if http.statusCode == 404 { throw APIError.notFound }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(status: http.statusCode) }
            return data
        } catch {
            throw APIError.wrap(error)
        }
    }

    func get(_ url: URL, query: [URLQueryItem] = []) async throws -> Data {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = (components.queryItems ?? []) + query }
        guard let finalURL = components.url else { throw APIError.invalidURL }
        return try await data(for: URLRequest(url: finalURL))
    }

    func postJSON(_ url: URL, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await data(for: request)
    }
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func decodeAPI<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decode(type, from: data)
        } catch {
            throw APIError.wrap(error)
        }
    }
}
