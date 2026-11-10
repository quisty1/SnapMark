// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "SnapMark", platforms: [.macOS(.v14)], products: [
    .executable(name: "SnapMark", targets: ["SnapMark"])
], targets: [
    .target(name: "SnapMarkCore"),
    .executableTarget(name: "SnapMark", dependencies: ["SnapMarkCore"], swiftSettings: [.defaultIsolation(MainActor.self)]),
    .executableTarget(name: "SnapMarkTests", dependencies: ["SnapMarkCore"], path: "Tests/SnapMarkCoreTests", swiftSettings: [.unsafeFlags(["-parse-as-library"])])
])
