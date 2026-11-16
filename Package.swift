// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MoleDesk",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.99.3"),
    ],
    targets: [
        .executableTarget(
            name: "MoleDesk",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/MoleDesk"
        ),
        .testTarget(
            name: "MoleDeskTests",
            dependencies: ["MoleDesk"],
            path: "Tests/MoleDeskTests"
        ),
    ]
)
