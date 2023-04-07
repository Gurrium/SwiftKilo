// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftKilo",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: .init(0, 1, 0))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "SwiftKilo",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),]
        ),
        .testTarget(
            name: "SwiftKiloTests",
            dependencies: ["SwiftKilo"]
        )
    ]
)
