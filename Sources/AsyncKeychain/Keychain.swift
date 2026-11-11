import Foundation
import LocalAuthentication
import Security

/// An immutable, `Sendable` handle to a set of keychain items.
///
/// A `Keychain` is only configuration: creating or copying one is free, and
/// the modifier methods return a new value.
///
///     let keychain = Keychain(service: "com.example.app")
///         .accessibility(.afterFirstUnlock)
///     try await keychain.set("secret", key: "token")
///     let token = try await keychain.get("token")
///
/// The Security framework has no asynchronous API and its calls block (for as
/// long as a Face ID / Touch ID prompt is on screen). Every operation therefore
/// runs on one private queue, off the caller's thread and off the Swift
/// concurrency pool. Reads run in parallel; a write waits for the operations
/// already in flight and then runs alone, so a write is atomic and a read
/// never observes it half-done. This holds across all `Keychain` values.
public struct Keychain: Sendable {
    var options: Options

    // MARK: Creating

    /// Generic passwords for `service`, by default the app's bundle identifier.
    public init(service: String = Bundle.main.bundleIdentifier ?? "", accessGroup: String? = nil) {
        options = Options(itemClass: .genericPassword, service: service, accessGroup: accessGroup)
    }

    /// Internet passwords for `server`.
    public init(
        server: URL,
        protocolType: ProtocolType,
        accessGroup: String? = nil,
        authenticationType: AuthenticationType = .default
    ) {
        options = Options(
            itemClass: .internetPassword,
            accessGroup: accessGroup,
            server: server,
            protocolType: protocolType,
            authenticationType: authenticationType
        )
    }

    // MARK: Configuration

    public var itemClass: ItemClass { options.itemClass }
    public var service: String { options.service }
    public var accessGroup: String? { options.accessGroup }
    public var server: URL? { options.server }
    public var accessibility: Accessibility { options.accessibility }
    public var authenticationPolicy: AuthenticationPolicy? { options.authenticationPolicy }
    public var synchronizable: Bool { options.synchronizable }
    public var label: String? { options.label }
    public var comment: String? { options.comment }
    public var authenticationPrompt: String? { options.authenticationPrompt }

    public func accessibility(_ accessibility: Accessibility) -> Keychain {
        with { $0.accessibility = accessibility }
    }

    /// Protects new items with Face ID / Touch ID / passcode.
    public func accessibility(_ accessibility: Accessibility, authenticationPolicy: AuthenticationPolicy) -> Keychain {
        with {
            $0.accessibility = accessibility
            $0.authenticationPolicy = authenticationPolicy
        }
    }

    /// Stores new items in iCloud Keychain.
    public func synchronizable(_ synchronizable: Bool) -> Keychain {
        with { $0.synchronizable = synchronizable }
    }

    public func label(_ label: String) -> Keychain {
        with { $0.label = label }
    }

    public func comment(_ comment: String) -> Keychain {
        with { $0.comment = comment }
    }

    /// Extra raw `kSecAttr…` attributes written with every item.
    public func attributes(_ attributes: [String: any Sendable]) -> Keychain {
        with { $0.extraAttributes.merge(attributes) { $1 } }
    }

    /// The reason shown in the system authentication prompt.
    public func authenticationPrompt(_ prompt: String) -> Keychain {
        with { $0.authenticationPrompt = prompt }
    }

    /// Reuses an already-evaluated `LAContext` so the user is not prompted again.
    /// The context is used from the keychain's private queue.
    public func authenticationContext(_ context: LAContext) -> Keychain {
        with { $0.authenticationContext = ContextBox(context) }
    }

    // MARK: Reading

    /// The string stored for `key`, or `nil` if there is no such item.
    public func get(_ key: String, ignoringAttributeSynchronizable: Bool = true) async throws -> String? {
        try await getString(key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
    }

    public func getString(_ key: String, ignoringAttributeSynchronizable: Bool = true) async throws -> String? {
        guard let data = try await getData(key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.conversionError
        }
        return string
    }

    public func getData(_ key: String, ignoringAttributeSynchronizable: Bool = true) async throws -> Data? {
        try await perform { try readData(key, ignoringSynchronizable: ignoringAttributeSynchronizable) }
    }

    /// The value and metadata stored for `key`, or `nil` if there is no such item.
    public func attributes(for key: String, ignoringAttributeSynchronizable: Bool = true) async throws -> Attributes? {
        try await perform { try readAttributes(key, ignoringSynchronizable: ignoringAttributeSynchronizable) }
    }

    /// Whether an item exists for `key`.
    ///
    /// With `withoutAuthenticationUI`, no Face ID / Touch ID prompt is shown and
    /// an item that exists but requires authentication is reported as present.
    public func contains(_ key: String, withoutAuthenticationUI: Bool = false) async throws -> Bool {
        try await perform { try exists(key, withoutAuthenticationUI: withoutAuthenticationUI) }
    }

    // MARK: Writing

    public func set(_ value: String, key: String, ignoringAttributeSynchronizable: Bool = true) async throws {
        try await set(Data(value.utf8), key: key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
    }

    /// Creates the item for `key`, or updates it if it already exists.
    public func set(_ value: Data, key: String, ignoringAttributeSynchronizable: Bool = true) async throws {
        try await perform(exclusive: true) {
            try write(value, key: key, ignoringSynchronizable: ignoringAttributeSynchronizable)
        }
    }

    /// Deletes the item for `key`. Does nothing if there is no such item.
    public func remove(_ key: String, ignoringAttributeSynchronizable: Bool = true) async throws {
        try await perform(exclusive: true) {
            try delete(key: key, ignoringSynchronizable: ignoringAttributeSynchronizable)
        }
    }

    /// Deletes every item of this service (or server).
    public func removeAll() async throws {
        try await perform(exclusive: true) { try delete(key: nil, ignoringSynchronizable: true) }
    }

    // MARK: Enumerating

    /// The keys of every item of this service (or server).
    public func allKeys() async throws -> [String] {
        try await allItems().compactMap(\.key)
    }

    /// Every item of this service (or server).
    public func allItems() async throws -> [Attributes] {
        try await perform { try Self.items(matching: baseQuery()) }
    }

    /// Every item of `itemClass` this app can see, across all services.
    public static func allItems(of itemClass: ItemClass) async throws -> [Attributes] {
        try await perform {
            try items(matching: [
                kSecClass as String: itemClass.rawValue,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
            ])
        }
    }

    // MARK: Private

    private func with(_ change: (inout Options) -> Void) -> Keychain {
        var copy = self
        change(&copy.options)
        return copy
    }

    private func perform<T: Sendable>(
        exclusive: Bool = false,
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Self.perform(exclusive: exclusive, work)
    }

    private static let queue = DispatchQueue(label: "AsyncKeychain", qos: .userInitiated, attributes: .concurrent)

    /// Runs `work` on the keychain queue. An `exclusive` operation (a write) is
    /// a barrier: it runs with no other operation in progress.
    private static func perform<T: Sendable>(
        exclusive: Bool = false,
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: exclusive ? .barrier : []) {
                continuation.resume(with: Result(catching: work))
            }
        }
    }
}

struct Options: Sendable {
    var itemClass: ItemClass
    var service = ""
    var accessGroup: String?
    var server: URL?
    var protocolType: ProtocolType?
    var authenticationType: AuthenticationType = .default
    var accessibility: Accessibility = .afterFirstUnlock
    var authenticationPolicy: AuthenticationPolicy?
    var synchronizable = false
    var label: String?
    var comment: String?
    var authenticationPrompt: String?
    var authenticationContext: ContextBox?
    var extraAttributes: [String: any Sendable] = [:]
}

/// `LAContext` is not `Sendable`. The box only carries the context to the
/// Security framework on the keychain's queue and never mutates it; the caller
/// must not mutate it while keychain operations that use it are running.
struct ContextBox: @unchecked Sendable {
    let context: LAContext

    init(_ context: LAContext) {
        self.context = context
    }
}
