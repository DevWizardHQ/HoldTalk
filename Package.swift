// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WizFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WizFlow",
            path: "Sources/WizFlow"
        )
    ]
)
