import Foundation

enum TagError: Error {
    case ResponseError(String)
    case Success
    case InvalidResponse
    case UnexpectedError
    case NotImplemented
}

extension TagError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .ResponseError(let msg): return msg
        case .Success: return "Success"
        case .InvalidResponse: return "Invalid response"
        case .UnexpectedError: return "Unexpected error"
        case .NotImplemented: return "Not implemented"
        }
    }
}
