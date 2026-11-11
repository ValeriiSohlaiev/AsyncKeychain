import Foundation
import Security

public enum ItemClass: Sendable, Hashable {
    case genericPassword
    case internetPassword

    var rawValue: String {
        switch self {
        case .genericPassword: kSecClassGenericPassword as String
        case .internetPassword: kSecClassInternetPassword as String
        }
    }
}

/// When the item's data may be read (`kSecAttrAccessible`).
public enum Accessibility: Sendable, Hashable, CaseIterable {
    case whenUnlocked
    case afterFirstUnlock
    case whenPasscodeSetThisDeviceOnly
    case whenUnlockedThisDeviceOnly
    case afterFirstUnlockThisDeviceOnly

    public var rawValue: String {
        switch self {
        case .whenUnlocked: kSecAttrAccessibleWhenUnlocked as String
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock as String
        case .whenPasscodeSetThisDeviceOnly: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String
        case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        }
    }

    public init?(rawValue: String) {
        guard let match = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = match
    }
}

/// Access-control requirements for an item (Face ID / Touch ID / passcode).
/// Raw values match `SecAccessControlCreateFlags`.
public struct AuthenticationPolicy: OptionSet, Sendable, Hashable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let userPresence = Self(.userPresence)
    public static let biometryAny = Self(.biometryAny)
    public static let biometryCurrentSet = Self(.biometryCurrentSet)
    public static let devicePasscode = Self(.devicePasscode)
    public static let or = Self(.or)
    public static let and = Self(.and)
    public static let privateKeyUsage = Self(.privateKeyUsage)
    public static let applicationPassword = Self(.applicationPassword)

    private init(_ flags: SecAccessControlCreateFlags) {
        self.rawValue = flags.rawValue
    }

    var flags: SecAccessControlCreateFlags {
        SecAccessControlCreateFlags(rawValue: rawValue)
    }
}

/// Protocol of an internet password (`kSecAttrProtocol`). The common protocols
/// are provided as constants; any other `kSecAttrProtocol*` value can be
/// wrapped with `init(rawValue:)`.
public struct ProtocolType: RawRepresentable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let http = Self(kSecAttrProtocolHTTP)
    public static let https = Self(kSecAttrProtocolHTTPS)
    public static let ftp = Self(kSecAttrProtocolFTP)
    public static let ftps = Self(kSecAttrProtocolFTPS)
    public static let ssh = Self(kSecAttrProtocolSSH)
    public static let smtp = Self(kSecAttrProtocolSMTP)
    public static let imap = Self(kSecAttrProtocolIMAP)
    public static let imaps = Self(kSecAttrProtocolIMAPS)
    public static let pop3 = Self(kSecAttrProtocolPOP3)
    public static let pop3s = Self(kSecAttrProtocolPOP3S)
    public static let ldap = Self(kSecAttrProtocolLDAP)
    public static let ldaps = Self(kSecAttrProtocolLDAPS)
    public static let smb = Self(kSecAttrProtocolSMB)
    public static let afp = Self(kSecAttrProtocolAFP)
    public static let telnet = Self(kSecAttrProtocolTelnet)

    private init(_ value: CFString) {
        self.rawValue = value as String
    }
}

/// Authentication scheme of an internet password (`kSecAttrAuthenticationType`).
public struct AuthenticationType: RawRepresentable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let `default` = Self(kSecAttrAuthenticationTypeDefault)
    public static let httpBasic = Self(kSecAttrAuthenticationTypeHTTPBasic)
    public static let httpDigest = Self(kSecAttrAuthenticationTypeHTTPDigest)
    public static let htmlForm = Self(kSecAttrAuthenticationTypeHTMLForm)
    public static let ntlm = Self(kSecAttrAuthenticationTypeNTLM)
    public static let msn = Self(kSecAttrAuthenticationTypeMSN)
    public static let dpa = Self(kSecAttrAuthenticationTypeDPA)
    public static let rpa = Self(kSecAttrAuthenticationTypeRPA)

    private init(_ value: CFString) {
        self.rawValue = value as String
    }
}

/// A snapshot of a keychain item: its key, value and metadata.
public struct Attributes: Sendable, Hashable {
    /// The item's key (`kSecAttrAccount`).
    public let key: String?
    /// The stored value. `nil` when the query did not return data
    /// (bulk queries on the macOS file-based keychain never do).
    public let data: Data?
    public let service: String?
    public let server: String?
    public let accessGroup: String?
    public let label: String?
    public let comment: String?
    public let accessibility: Accessibility?
    public let synchronizable: Bool?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let persistentRef: Data?

    /// The stored value decoded as UTF-8, if it is a string.
    public var value: String? {
        data.flatMap { String(data: $0, encoding: .utf8) }
    }

    init(_ item: [String: Any]) {
        func string(_ key: CFString) -> String? { item[key as String] as? String }

        key = string(kSecAttrAccount)
        data = item[kSecValueData as String] as? Data
        service = string(kSecAttrService)
        server = string(kSecAttrServer)
        accessGroup = string(kSecAttrAccessGroup)
        label = string(kSecAttrLabel)
        comment = string(kSecAttrComment)
        accessibility = string(kSecAttrAccessible).flatMap(Accessibility.init(rawValue:))
        synchronizable = item[kSecAttrSynchronizable as String] as? Bool
        creationDate = item[kSecAttrCreationDate as String] as? Date
        modificationDate = item[kSecAttrModificationDate as String] as? Date
        persistentRef = item[kSecValuePersistentRef as String] as? Data
    }
}
