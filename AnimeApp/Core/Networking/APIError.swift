import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case http(status: Int)
    case decoding(String)
    case transport(String)
    case notFound
    case sourceUnavailable(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес запроса."
        case .http(let status) where status == 429:
            return "Слишком много запросов. Подождите немного и попробуйте снова."
        case .http(let status) where status >= 500:
            return "Сервер временно недоступен (код \(status))."
        case .http(let status):
            return "Ошибка сервера (код \(status))."
        case .decoding:
            return "Не удалось разобрать ответ сервера."
        case .transport(let message):
            return "Нет соединения: \(message)"
        case .notFound:
            return "Ничего не найдено."
        case .sourceUnavailable(let name):
            return "Источник «\(name)» недоступен."
        case .server(let message):
            return message
        }
    }

    static func wrap(_ error: Error) -> Error {
        if error is APIError || error is CancellationError { return error }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return CancellationError() }
            return APIError.transport(urlError.localizedDescription)
        }
        if let decoding = error as? DecodingError {
            return APIError.decoding(String(describing: decoding))
        }
        return error
    }
}
