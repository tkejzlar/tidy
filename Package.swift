// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tidy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TidyCore", targets: ["TidyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TidyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "TidyCoreTests",
            dependencies: ["TidyCore"]
        ),
    ]
)
