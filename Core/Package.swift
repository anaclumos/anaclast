// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnaclastCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AnaclastCore", targets: ["AnaclastCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/FuzzyMatch.git", exact: "1.4.0")
    ],
    targets: [
        .target(name: "AnaclastCore", dependencies: ["FuzzyMatch"]),
        .testTarget(name: "AnaclastCoreTests", dependencies: ["AnaclastCore"])
    ]
)
