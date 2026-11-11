# AsyncKeychain

[![Swift](https://img.shields.io/badge/Swift-6.0%2B-F05138?style=flat-square)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS_macOS_Mac_Catalyst_visionOS-yellowgreen?style=flat-square)](#asynckeychain)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](#installation)
[![CI](https://img.shields.io/github/actions/workflow/status/ValeriiSohlaiev/AsyncKeychain/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/ValeriiSohlaiev/AsyncKeychain/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

A small Swift 6 wrapper around the keychain with an `async`/`await` API.
A from-scratch rewrite of the core of [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess).

- `Keychain` is an immutable `Sendable` struct, safe to share between tasks and actors.
- Every operation is `async throws` and runs off the caller's thread, so a Face ID prompt never blocks the main thread or the Swift concurrency pool.
- Errors are a single `KeychainError` carrying the `OSStatus`.

**Requirements:** iOS 15, macOS 12, Mac Catalyst 15, visionOS 1 · Swift 6 (Xcode 16 or later).

> **Status: 0.x.** The API may still change between minor versions. Biometric prompts, iCloud sync and access groups are not covered by the automated tests.

## Installation

In Xcode: **File → Add Package Dependencies…** and enter the repository URL.

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ValeriiSohlaiev/AsyncKeychain.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["AsyncKeychain"])
]
```

## Basic usage

```swift
import AsyncKeychain

let keychain = Keychain(service: "com.example.app")

// Save (creates the item or updates an existing one)
try await keychain.set("s3cr3t", key: "token")

// Read — nil when there is no such item
let token = try await keychain.get("token")

// Binary data
try await keychain.set(Data([0x01, 0x02]), key: "blob")
let blob = try await keychain.getData("blob")

// Check, delete
let exists = try await keychain.contains("token")
try await keychain.remove("token")   // no error if the item is missing
try await keychain.removeAll()       // everything stored for this service
```

`Keychain()` without arguments uses the app's bundle identifier as the service.

## Configuration

Modifiers return a new `Keychain`; the original is not changed.

```swift
let keychain = Keychain(service: "com.example.app", accessGroup: "ABCDE12345.com.example.shared")
    .accessibility(.afterFirstUnlockThisDeviceOnly)
    .synchronizable(true)            // iCloud Keychain
    .label("Example token")
    .comment("Issued by api.example.com")

try await keychain.set("s3cr3t", key: "token")
```

Accessibility options: `.whenUnlocked`, `.afterFirstUnlock` (default), `.whenPasscodeSetThisDeviceOnly`, `.whenUnlockedThisDeviceOnly`, `.afterFirstUnlockThisDeviceOnly`.

Any other `kSecAttr…` attribute can be passed as is:

```swift
let keychain = Keychain(service: "com.example.app")
    .attributes([kSecAttrDescription as String: "API token"])
```

## Face ID / Touch ID

Protect an item when saving it:

```swift
let secure = Keychain(service: "com.example.app")
    .accessibility(.whenPasscodeSetThisDeviceOnly, authenticationPolicy: [.biometryCurrentSet])

try await secure.set("s3cr3t", key: "token")
```

Reading it shows the system prompt. The call suspends until the user answers:

```swift
do {
    let token = try await secure
        .authenticationPrompt("Authenticate to sign in")
        .get("token")
} catch KeychainError.userCanceled {
    // the user dismissed the prompt
} catch KeychainError.authFailed {
    // authentication failed
}
```

Check that a protected item exists **without** showing the prompt:

```swift
let hasToken = try await secure.contains("token", withoutAuthenticationUI: true)
```

Reuse an `LAContext` the user has already authenticated with, to avoid a second prompt:

```swift
import LocalAuthentication

let context = LAContext()
try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Sign in")

let token = try await secure.authenticationContext(context).get("token")
```

Available policies: `.userPresence`, `.biometryAny`, `.biometryCurrentSet`, `.devicePasscode`, `.applicationPassword`, `.privateKeyUsage`, combined with `.or` / `.and`, for example `[.biometryAny, .or, .devicePasscode]`.

Add `NSFaceIDUsageDescription` to the app's Info.plist, otherwise the app is terminated on the first Face ID prompt.

## Listing items and metadata

```swift
let keys = try await keychain.allKeys()        // ["token", "blob"]
let items = try await keychain.allItems()      // [Attributes]

if let item = try await keychain.attributes(for: "token") {
    item.key               // "token"
    item.value             // "s3cr3t" (nil if the data is not UTF-8)
    item.data              // raw Data
    item.label
    item.comment
    item.accessibility
    item.synchronizable
    item.creationDate
    item.modificationDate
}

// Everything this app can see, across all services
let everything = try await Keychain.allItems(of: .genericPassword)
```

On macOS `allItems()` returns metadata only (`data` and `value` are `nil`); use `attributes(for:)` or `get` to read a value.

## Internet passwords

```swift
let keychain = Keychain(server: URL(string: "https://example.com")!, protocolType: .https)

try await keychain.set("p@ssw0rd", key: "user@example.com")
let password = try await keychain.get("user@example.com")
```

An authentication scheme can be given with `authenticationType:` (`.httpBasic`, `.htmlForm`, …). Protocols not in the list of constants: `ProtocolType(rawValue: kSecAttrProtocolIRC as String)`.

## Error handling

`KeychainError` wraps the `OSStatus` returned by the Security framework. Common codes are constants and can be matched directly in `catch`:

```swift
do {
    try await keychain.set("s3cr3t", key: "token")
} catch KeychainError.interactionNotAllowed {
    // the device is locked
} catch KeychainError.missingEntitlement {
    // wrong access group, or the code is not running inside a signed app
} catch let error as KeychainError {
    print(error.status, error.localizedDescription)
}
```

Constants: `.itemNotFound`, `.duplicateItem`, `.authFailed`, `.userCanceled`, `.interactionNotAllowed`, `.missingEntitlement`, `.notAvailable`, `.param`, `.decode`, `.conversionError`, `.unexpectedError`. Any other status: `KeychainError(status: errSec…)`.

A missing item is not an error: `get` returns `nil`, `contains` returns `false`, `remove` does nothing.

`KeychainError` bridges to `NSError` (domain `AsyncKeychain.KeychainError`, code = `OSStatus`), so it can be passed to crash reporters as is.

## Migrating from KeychainAccess

| KeychainAccess | AsyncKeychain |
|---|---|
| `try keychain.get("k")` | `try await keychain.get("k")` |
| `keychain["k"] = "v"` | `try await keychain.set("v", key: "k")` |
| `keychain["k"] = nil` | `try await keychain.remove("k")` |
| `catch Status.authFailed` | `catch KeychainError.authFailed` |
| `keychain.get("k") { attributes in … }` | `try await keychain.attributes(for: "k")` |
| `keychain.allItems()` → `[[String: Any]]` | `try await keychain.allItems()` → `[Attributes]` |
| `Keychain.allKeys(.genericPassword)` | `try await Keychain.allItems(of: .genericPassword)` |
| `.authenticationUI(.fail)` | `contains(_:withoutAuthenticationUI: true)` |

A completion-handler wrapper with its own queue becomes a plain `async` function:

```swift
// Before
static func contains(_ key: String, withoutAuthenticationUI: Bool, completion: @Sendable @escaping (Bool) -> Void) {
    queue.sync {
        do {
            completion(try keychain.contains(key, withoutAuthenticationUI: withoutAuthenticationUI))
        } catch KeychainAccess.Status.authFailed {
            completion(false)
        } catch {
            logCrashlytics(error: error)
            completion(false)
        }
    }
}

// After
static func contains(_ key: String, withoutAuthenticationUI: Bool) async -> Bool {
    do {
        return try await keychain.contains(key, withoutAuthenticationUI: withoutAuthenticationUI)
    } catch KeychainError.authFailed {
        return false
    } catch {
        logCrashlytics(error: error)
        return false
    }
}
```

Not carried over: subscripts, Shared Web Credentials, `authenticationUI(.allow/.skip)`, tvOS and watchOS.

## Threading

All operations run on one private queue shared by every `Keychain` value. Reads (`get`, `getData`, `contains`, `attributes(for:)`, `allKeys`, `allItems`) run in parallel. Writes (`set`, `remove`, `removeAll`) are barriers: a write waits for the operations already in flight and then runs alone.

- `set` (update, then add if missing) is atomic, and a read never sees it half-done.
- A Face ID prompt opened by one read does not block other reads. A write issued while the prompt is on screen waits until the user answers.
- Operations awaited one after another run in that order. Operations started from separate unstructured `Task`s have no guaranteed order.

## Tests

On macOS:

```bash
swift test
```

On iOS the keychain works only inside a signed app, so the same tests run inside the host app in `TestHost/`:

```bash
cd TestHost && xcodebuild test -project TestHost.xcodeproj -scheme TestHost -destination "platform=iOS Simulator,name=iPhone 16 Pro"
```

Biometric prompts, iCloud sync and access groups are not covered by the automated tests; they need a real device and entitlements.

## License

MIT, see [LICENSE](LICENSE). The API design follows [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) by kishikawa katsumi (MIT).
