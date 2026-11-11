import Foundation
import Security

/// An error reported by the Security framework, identified by its `OSStatus`.
///
/// Replaces the 400-case `Status` enum of KeychainAccess: any status code is
/// representable, and the common ones are available as static constants so
/// they can be matched directly:
///
///     do { ... } catch KeychainError.authFailed { ... }
public struct KeychainError: Error, Hashable, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public static let itemNotFound = KeychainError(status: errSecItemNotFound)
    public static let duplicateItem = KeychainError(status: errSecDuplicateItem)
    public static let authFailed = KeychainError(status: errSecAuthFailed)
    public static let userCanceled = KeychainError(status: errSecUserCanceled)
    public static let interactionNotAllowed = KeychainError(status: errSecInteractionNotAllowed)
    public static let missingEntitlement = KeychainError(status: errSecMissingEntitlement)
    public static let notAvailable = KeychainError(status: errSecNotAvailable)
    public static let param = KeychainError(status: errSecParam)
    public static let decode = KeychainError(status: errSecDecode)
    /// The stored data is not valid UTF-8, or a string could not be encoded.
    public static let conversionError = KeychainError(status: errSecConversionError)
    /// The Security framework returned a result of an unexpected type.
    public static let unexpectedError = KeychainError(status: -99999)

    /// Enables `catch KeychainError.authFailed` on an untyped `Error`.
    public static func ~= (pattern: KeychainError, error: any Error) -> Bool {
        (error as? KeychainError) == pattern
    }
}

extension KeychainError: CustomStringConvertible, LocalizedError, CustomNSError {
    public var description: String {
        if self == .unexpectedError {
            return "Unexpected error has occurred."
        }
        return SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }

    public var errorDescription: String? { description }

    public static var errorDomain: String { "AsyncKeychain.KeychainError" }
    public var errorCode: Int { Int(status) }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: description] }
}
