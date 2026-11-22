// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MIDIReconfigure",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MIDIReconfigure", targets: ["MIDIReconfigure"])
    ],
    targets: [
        .target(name: "MIDIRouting"),
        .target(name: "AppSupport"),
        .executableTarget(name: "MIDIReconfigure", dependencies: ["MIDIRouting", "AppSupport"]),
        .testTarget(name: "MIDIRoutingTests", dependencies: ["MIDIRouting"]),
        .testTarget(name: "AppSupportTests", dependencies: ["AppSupport"])
    ]
)
