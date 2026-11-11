// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AsyncKeychain",
    platforms: [
        .iOS(.v15), .macOS(.v12), .macCatalyst(.v15), .visionOS(.v1)
    ],
    products: [
        .library(name: "AsyncKeychain", targets: ["AsyncKeychain"])
    ],
    targets: [
        .target(name: "AsyncKeychain"),
        .testTarget(name: "AsyncKeychainTests", dependencies: ["AsyncKeychain"])
    ],
    swiftLanguageModes: [.v6]
)
