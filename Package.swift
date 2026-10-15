// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Vela", platforms: [.macOS(.v14)], products: [.executable(name: "Vela", targets: ["Vela"]), .executable(name: "GestureChecks", targets: ["GestureChecks"])], targets: [.target(name: "GestureCore"), .executableTarget(name: "Vela", dependencies: ["GestureCore"], swiftSettings: [.swiftLanguageMode(.v5)]), .executableTarget(name: "GestureChecks", dependencies: ["GestureCore"])])
