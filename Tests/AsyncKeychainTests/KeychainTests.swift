import Foundation
import Testing
@testable import AsyncKeychain

/// Runs `body` against a keychain with a unique service and removes whatever
/// it stored, so tests are isolated from each other and leave nothing behind.
private func withKeychain(
    _ configure: (Keychain) -> Keychain = { $0 },
    _ body: (Keychain) async throws -> Void
) async throws {
    let keychain = configure(Keychain(service: "AsyncKeychainTests.\(UUID().uuidString)"))
    do {
        try await body(keychain)
    } catch {
        try? await keychain.removeAll()
        throw error
    }
    try await keychain.removeAll()
}

@Suite struct ReadWriteTests {
    @Test func missingKeyReturnsNil() async throws {
        try await withKeychain { keychain in
            let string = try await keychain.get("missing")
            let data = try await keychain.getData("missing")
            let attributes = try await keychain.attributes(for: "missing")
            #expect(string == nil)
            #expect(data == nil)
            #expect(attributes == nil)
        }
    }

    @Test func stringRoundTrip() async throws {
        try await withKeychain { keychain in
            try await keychain.set("secret", key: "token")
            #expect(try await keychain.get("token") == "secret")
            #expect(try await keychain.getString("token") == "secret")
        }
    }

    @Test func dataRoundTrip() async throws {
        try await withKeychain { keychain in
            let data = Data([0x00, 0xFF, 0x10, 0x80])
            try await keychain.set(data, key: "blob")
            #expect(try await keychain.getData("blob") == data)
        }
    }

    @Test func nonUTF8DataIsNotAString() async throws {
        try await withKeychain { keychain in
            try await keychain.set(Data([0xFF, 0xFE]), key: "blob")
            await #expect(throws: KeychainError.conversionError) {
                try await keychain.getString("blob")
            }
        }
    }

    @Test func setOverwritesExistingValue() async throws {
        try await withKeychain { keychain in
            try await keychain.set("first", key: "token")
            try await keychain.set("second", key: "token")
            #expect(try await keychain.get("token") == "second")
            #expect(try await keychain.allKeys() == ["token"])
        }
    }

    @Test(arguments: ["", "пароль 🔐", "line\nbreak", String(repeating: "x", count: 10_000)])
    func unusualValues(value: String) async throws {
        try await withKeychain { keychain in
            try await keychain.set(value, key: "key")
            #expect(try await keychain.get("key") == value)
        }
    }

    @Test func unicodeKey() async throws {
        try await withKeychain { keychain in
            try await keychain.set("value", key: "ключ 🔑")
            #expect(try await keychain.get("ключ 🔑") == "value")
            #expect(try await keychain.contains("ключ 🔑"))
        }
    }

    @Test func servicesAreIsolated() async throws {
        try await withKeychain { first in
            try await withKeychain { second in
                try await first.set("one", key: "shared")
                try await second.set("two", key: "shared")
                #expect(try await first.get("shared") == "one")
                #expect(try await second.get("shared") == "two")

                try await first.removeAll()
                #expect(try await second.get("shared") == "two")
            }
        }
    }
}

@Suite struct RemoveAndContainsTests {
    @Test func remove() async throws {
        try await withKeychain { keychain in
            try await keychain.set("a", key: "one")
            try await keychain.set("b", key: "two")
            try await keychain.remove("one")
            #expect(try await keychain.get("one") == nil)
            #expect(try await keychain.get("two") == "b")
        }
    }

    @Test func removingMissingKeyDoesNotThrow() async throws {
        try await withKeychain { keychain in
            try await keychain.remove("missing")
            try await keychain.removeAll()
        }
    }

    @Test func removeAll() async throws {
        try await withKeychain { keychain in
            for key in ["one", "two", "three"] {
                try await keychain.set("value", key: key)
            }
            try await keychain.removeAll()
            #expect(try await keychain.allKeys().isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func contains(withoutAuthenticationUI: Bool) async throws {
        try await withKeychain { keychain in
            #expect(try await keychain.contains("token", withoutAuthenticationUI: withoutAuthenticationUI) == false)
            try await keychain.set("secret", key: "token")
            #expect(try await keychain.contains("token", withoutAuthenticationUI: withoutAuthenticationUI))
            try await keychain.remove("token")
            #expect(try await keychain.contains("token", withoutAuthenticationUI: withoutAuthenticationUI) == false)
        }
    }
}

@Suite struct EnumerationTests {
    @Test func allKeys() async throws {
        try await withKeychain { keychain in
            #expect(try await keychain.allKeys().isEmpty)
            try await keychain.set("a", key: "one")
            try await keychain.set("b", key: "two")
            #expect(try await keychain.allKeys().sorted() == ["one", "two"])
        }
    }

    @Test func allItems() async throws {
        try await withKeychain { keychain in
            try await keychain.set("a", key: "one")
            try await keychain.set("b", key: "two")

            let items = try await keychain.allItems().sorted { ($0.key ?? "") < ($1.key ?? "") }
            #expect(items.map(\.key) == ["one", "two"])
            #expect(items.allSatisfy { $0.service == keychain.service })
            #if !os(macOS)
            #expect(items.map(\.value) == ["a", "b"])
            #endif
        }
    }

    @Test func attributesOfItem() async throws {
        try await withKeychain({ $0.label("My label").comment("My comment") }) { keychain in
            let start = Date().addingTimeInterval(-5)
            try await keychain.set("secret", key: "token")

            let attributes = try #require(try await keychain.attributes(for: "token"))
            #expect(attributes.key == "token")
            #expect(attributes.value == "secret")
            #expect(attributes.data == Data("secret".utf8))
            #expect(attributes.service == keychain.service)
            #expect(attributes.label == "My label")
            #expect(attributes.comment == "My comment")
            #expect(attributes.persistentRef != nil)
            #expect(try #require(attributes.creationDate) > start)
            #expect(try #require(attributes.modificationDate) > start)
        }
    }

    @Test func labelAndCommentAreUpdated() async throws {
        try await withKeychain { keychain in
            try await keychain.set("secret", key: "token")
            try await keychain.label("New label").comment("New comment").set("secret2", key: "token")

            let attributes = try #require(try await keychain.attributes(for: "token"))
            #expect(attributes.value == "secret2")
            #expect(attributes.label == "New label")
            #expect(attributes.comment == "New comment")
        }
    }

    @Test func extraAttributesAreWritten() async throws {
        try await withKeychain({ $0.attributes([kSecAttrDescription as String: "Custom kind"]) }) { keychain in
            try await keychain.set("secret", key: "token")
            #expect(try await keychain.get("token") == "secret")
        }
    }
}

@Suite struct InternetPasswordTests {
    @Test func roundTrip() async throws {
        let host = "\(UUID().uuidString.lowercased()).example.com"
        let keychain = Keychain(server: try #require(URL(string: "https://\(host):8443")), protocolType: .https)
        let other = Keychain(server: try #require(URL(string: "https://other-\(host)")), protocolType: .https)

        try await keychain.set("password", key: "user")
        #expect(try await keychain.get("user") == "password")
        #expect(try await keychain.contains("user"))
        #expect(try await keychain.allKeys() == ["user"])
        #expect(try await keychain.attributes(for: "user")?.server == host)
        #expect(try await other.get("user") == nil)

        try await keychain.removeAll()
        #expect(try await keychain.get("user") == nil)
    }
}

@Suite struct ConfigurationTests {
    @Test func modifiersReturnModifiedCopies() {
        let base = Keychain(service: "service", accessGroup: "group")
        let modified = base
            .accessibility(.whenUnlocked, authenticationPolicy: [.biometryAny, .or, .devicePasscode])
            .synchronizable(true)
            .label("label")
            .comment("comment")
            .authenticationPrompt("prompt")

        #expect(base.itemClass == .genericPassword)
        #expect(base.service == "service")
        #expect(base.accessGroup == "group")
        #expect(base.accessibility == .afterFirstUnlock)
        #expect(base.authenticationPolicy == nil)
        #expect(base.synchronizable == false)
        #expect(base.label == nil)

        #expect(modified.accessibility == .whenUnlocked)
        #expect(modified.authenticationPolicy == [.biometryAny, .or, .devicePasscode])
        #expect(modified.synchronizable)
        #expect(modified.label == "label")
        #expect(modified.comment == "comment")
        #expect(modified.authenticationPrompt == "prompt")
    }

    @Test func internetPasswordConfiguration() throws {
        let url = try #require(URL(string: "https://example.com"))
        let keychain = Keychain(server: url, protocolType: .https, authenticationType: .htmlForm)
        #expect(keychain.itemClass == .internetPassword)
        #expect(keychain.server == url)
    }

    @Test func queryRespectsSynchronizableFlag() {
        let keychain = Keychain(service: "service").synchronizable(true)
        let key = kSecAttrSynchronizable as String

        #expect(keychain.baseQuery()[key] as? String == kSecAttrSynchronizableAny as String)
        #expect(keychain.baseQuery(ignoringSynchronizable: false)[key] as? Bool == true)
    }

    @Test(arguments: Accessibility.allCases)
    func accessibilityRawValueRoundTrip(accessibility: Accessibility) {
        #expect(Accessibility(rawValue: accessibility.rawValue) == accessibility)
    }

    @Test func authenticationPolicyMatchesSecurityFlags() {
        #expect(AuthenticationPolicy.userPresence.flags == .userPresence)
        #expect(AuthenticationPolicy([.biometryCurrentSet, .and, .devicePasscode]).flags
            == [.biometryCurrentSet, .and, .devicePasscode])
    }
}

@Suite struct ErrorTests {
    @Test func constantsMatchSecurityStatusCodes() {
        #expect(KeychainError.itemNotFound.status == errSecItemNotFound)
        #expect(KeychainError.authFailed.status == errSecAuthFailed)
        #expect(KeychainError.userCanceled.status == errSecUserCanceled)
        #expect(KeychainError.interactionNotAllowed.status == errSecInteractionNotAllowed)
        #expect(KeychainError(status: errSecAuthFailed) == .authFailed)
    }

    @Test func catchPatternMatchesSpecificError() {
        func classify(_ error: any Error) -> String {
            do {
                throw error
            } catch KeychainError.authFailed {
                return "authFailed"
            } catch {
                return "other"
            }
        }

        #expect(classify(KeychainError.authFailed) == "authFailed")
        #expect(classify(KeychainError.itemNotFound) == "other")
        #expect(classify(CancellationError()) == "other")
    }

    @Test func descriptionAndNSErrorBridging() {
        let error = KeychainError.itemNotFound
        #expect(!error.description.isEmpty)
        #expect(error.localizedDescription == error.description)

        let nsError = error as NSError
        #expect(nsError.domain == "AsyncKeychain.KeychainError")
        #expect(nsError.code == Int(errSecItemNotFound))
    }
}

@Suite struct ConcurrencyTests {
    @Test func concurrentWritesToDifferentKeys() async throws {
        try await withKeychain { keychain in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<50 {
                    group.addTask { try await keychain.set("value-\(index)", key: "key-\(index)") }
                }
                try await group.waitForAll()
            }

            #expect(try await keychain.allKeys().count == 50)
            for index in 0..<50 {
                #expect(try await keychain.get("key-\(index)") == "value-\(index)")
            }
        }
    }

    @Test func concurrentWritesToSameKeyLeaveOneItem() async throws {
        try await withKeychain { keychain in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<50 {
                    group.addTask { try await keychain.set("value-\(index)", key: "key") }
                }
                try await group.waitForAll()
            }

            #expect(try await keychain.allKeys() == ["key"])
            #expect(try #require(try await keychain.get("key")).hasPrefix("value-"))
        }
    }

    @Test func usableFromMainActor() async throws {
        try await withKeychain { keychain in
            let value = try await Task { @MainActor in
                try await keychain.set("secret", key: "token")
                return try await keychain.get("token")
            }.value
            #expect(value == "secret")
        }
    }
}
