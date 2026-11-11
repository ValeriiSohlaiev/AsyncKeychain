import Foundation
import LocalAuthentication
import Security

/// The synchronous Security framework calls. Everything here runs on the
/// keychain's private queue; the writes run as barriers.
extension Keychain {
    func baseQuery(ignoringSynchronizable: Bool = true, withoutAuthenticationUI: Bool = false) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: options.itemClass.rawValue]

        if let accessGroup = options.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if ignoringSynchronizable {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        } else {
            query[kSecAttrSynchronizable as String] = options.synchronizable
        }

        switch options.itemClass {
        case .genericPassword:
            query[kSecAttrService as String] = options.service
        case .internetPassword:
            query[kSecAttrServer as String] = options.server?.host
            query[kSecAttrPort as String] = options.server?.port
            query[kSecAttrProtocol as String] = options.protocolType?.rawValue
            query[kSecAttrAuthenticationType as String] = options.authenticationType.rawValue
        }

        if let context = authenticationContext(withoutUI: withoutAuthenticationUI) {
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    /// `kSecUseAuthenticationUI` and `kSecUseOperationPrompt` are deprecated;
    /// an `LAContext` carries both the "no UI" flag and the prompt text.
    private func authenticationContext(withoutUI: Bool) -> LAContext? {
        if withoutUI {
            let context = LAContext()
            context.interactionNotAllowed = true
            return context
        }
        if let context = options.authenticationContext?.context {
            return context
        }
        if let prompt = options.authenticationPrompt {
            let context = LAContext()
            context.localizedReason = prompt
            return context
        }
        return nil
    }

    func readData(_ key: String, ignoringSynchronizable: Bool) throws -> Data? {
        var query = baseQuery(ignoringSynchronizable: ignoringSynchronizable)
        query[kSecAttrAccount as String] = key
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.unexpectedError }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func readAttributes(_ key: String, ignoringSynchronizable: Bool) throws -> Attributes? {
        var query = baseQuery(ignoringSynchronizable: ignoringSynchronizable)
        query[kSecAttrAccount as String] = key
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecReturnPersistentRef as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let item = result as? [String: Any] else { throw KeychainError.unexpectedError }
            return Attributes(item)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func exists(_ key: String, withoutAuthenticationUI: Bool) throws -> Bool {
        var query = baseQuery(withoutAuthenticationUI: withoutAuthenticationUI)
        query[kSecAttrAccount as String] = key

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecInteractionNotAllowed:
            // The item is there but reading it needs authentication.
            return withoutAuthenticationUI
        case errSecItemNotFound:
            return false
        default:
            throw KeychainError(status: status)
        }
    }

    func write(_ value: Data, key: String, ignoringSynchronizable: Bool) throws {
        var query = baseQuery(ignoringSynchronizable: ignoringSynchronizable)
        query[kSecAttrAccount as String] = key

        var status = SecItemUpdate(query as CFDictionary, try itemAttributes(value: value) as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery()
            item[kSecAttrAccount as String] = key
            item.merge(try itemAttributes(value: value)) { $1 }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func itemAttributes(value: Data) throws -> [String: Any] {
        var attributes: [String: Any] = [kSecValueData as String: value]
        attributes[kSecAttrLabel as String] = options.label
        attributes[kSecAttrComment as String] = options.comment

        if let policy = options.authenticationPolicy {
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault, options.accessibility.rawValue as CFString, policy.flags, &error
            ) else {
                throw error?.takeRetainedValue() as (any Error)? ?? KeychainError.unexpectedError
            }
            attributes[kSecAttrAccessControl as String] = accessControl
        } else {
            attributes[kSecAttrAccessible as String] = options.accessibility.rawValue
        }
        attributes[kSecAttrSynchronizable as String] = options.synchronizable

        attributes.merge(options.extraAttributes) { $1 }
        return attributes
    }

    /// Deletes the item for `key`, or every item of the service when `key` is `nil`.
    func delete(key: String?, ignoringSynchronizable: Bool) throws {
        var query = baseQuery(ignoringSynchronizable: ignoringSynchronizable)
        if let key {
            query[kSecAttrAccount as String] = key
        } else {
            #if os(macOS)
            // The file-based keychain deletes only the first match by default.
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            #endif
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    static func items(matching baseQuery: [String: Any]) throws -> [Attributes] {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        #if !os(macOS)
        // The macOS file-based keychain rejects bulk queries that return data.
        query[kSecReturnData as String] = true
        #endif

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else { throw KeychainError.unexpectedError }
            return items.map(Attributes.init)
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError(status: status)
        }
    }
}
