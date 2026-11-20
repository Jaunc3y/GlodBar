// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "GoldBar", platforms: [.macOS(.v15)], products: [.library(name: "GoldCore", targets: ["GoldCore"])], targets: [.target(name: "GoldCore"), .target(name: "GoldUI", dependencies: ["GoldCore"]), .executableTarget(name: "GoldBar", dependencies: ["GoldUI"]), .executableTarget(name: "UITests", dependencies: ["GoldUI", "GoldCore"], path: "Tests/UITests"), .executableTarget(name: "CoreTests", dependencies: ["GoldCore"], path: "Tests/CoreTests")])
