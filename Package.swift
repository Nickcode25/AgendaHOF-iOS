// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AgendaHOF",
    platforms: [
        .iOS(.v17),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "AgendaHOF",
            targets: ["AgendaHOF"]
        )
    ],
    dependencies: [
        // Supabase SDK para autenticação e database
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "AgendaHOF",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: ".",
            exclude: [
                "Tests",
                "AgendaHOF.xcodeproj",
                "Preview Content",
                "AgendaWidget"
            ]
        ),
        .testTarget(
            name: "AgendaHOFTests",
            dependencies: ["AgendaHOF"],
            path: "Tests"
        )
    ]
)
