// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "M230Controller",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "M230Controller", targets: ["M230Controller"]),
    .library(name: "M230Core", targets: ["M230Core"]),
  ],
  targets: [
    .target(name: "M230Core"),
    .executableTarget(name: "M230Controller", dependencies: ["M230Core"]),
    .testTarget(name: "M230CoreTests", dependencies: ["M230Core"]),
  ]
)
