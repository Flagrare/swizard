// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SWizard",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SWizard", targets: ["SWizard"])
    ],
    targets: [
        // C Bridge — wraps libusb for Swift import
        .systemLibrary(
            name: "CLibUSB",
            pkgConfig: "libusb-1.0",
            providers: [.brew(["libusb"])]
        ),

        // Infrastructure — USB device communication
        .target(
            name: "USBTransport",
            dependencies: ["CLibUSB"]
        ),

        // Domain — DBI protocol encode/decode and command handling
        .target(
            name: "DBIProtocol"
        ),

        // Orchestration — wires protocol + USB + file serving
        .target(
            name: "Installer",
            dependencies: ["USBTransport", "DBIProtocol"]
        ),

        // Presentation — SwiftUI app
        .executableTarget(
            name: "SWizard",
            dependencies: ["Installer"]
        ),

        // Tests
        .testTarget(
            name: "DBIProtocolTests",
            dependencies: ["DBIProtocol"]
        ),
        .testTarget(
            name: "InstallerTests",
            dependencies: ["Installer"]
        ),
    ]
)
