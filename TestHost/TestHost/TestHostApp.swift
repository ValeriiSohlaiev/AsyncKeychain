import SwiftUI

/// An empty app whose only job is to host the keychain tests: on iOS the
/// keychain is available only to code running inside a signed application.
@main
struct TestHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("AsyncKeychain test host")
        }
    }
}
