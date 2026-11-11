# Changelog

This project follows [Semantic Versioning](https://semver.org). While the version is 0.x, the API may change between minor versions.

## 0.1.0 — unreleased

Initial version.

- `Keychain`: an immutable `Sendable` handle with `async throws` operations — `get`, `getString`, `getData`, `set`, `remove`, `removeAll`, `contains`, `attributes(for:)`, `allKeys`, `allItems`.
- Generic and internet passwords, access groups, accessibility, iCloud synchronization, labels, comments, custom attributes.
- Face ID / Touch ID: `authenticationPolicy`, `authenticationPrompt`, `authenticationContext`, `contains(_:withoutAuthenticationUI:)`.
- `KeychainError` carrying the `OSStatus`, matchable in `catch`.
- Reads run in parallel; writes are exclusive.
- iOS 15, macOS 12, Mac Catalyst 15, visionOS 1.
