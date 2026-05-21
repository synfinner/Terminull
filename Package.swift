// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Terminull",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Terminull", targets: ["Terminull"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "Terminull",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Terminull",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "TerminullTests",
            dependencies: ["Terminull"],
            path: "Tests/TerminullTests"
        )
    ]
)
