// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeviceDiagnosticSuite",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "DeviceDiagnosticSuite", targets: ["DeviceDiagnosticSuite"])],
    targets: [
        .executableTarget(name: "DeviceDiagnosticSuite", exclude: ["Resources"]),
        .testTarget(name: "DeviceDiagnosticSuiteTests", dependencies: ["DeviceDiagnosticSuite"], resources: [.copy("Fixtures")])
    ]
)
