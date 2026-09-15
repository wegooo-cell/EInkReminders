// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EInkRemindersMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EInkRemindersMac", targets: ["EInkRemindersMac"])
    ],
    targets: [
        .executableTarget(name: "EInkRemindersMac"),
        .testTarget(
            name: "EInkRemindersMacTests",
            dependencies: ["EInkRemindersMac"]
        )
    ]
)

