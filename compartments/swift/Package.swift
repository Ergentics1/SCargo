// swift-tools-version: 6.4
// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import PackageDescription

let package = Package(
    name: "SCargoSwift",
    products: [
        .library(
            name: "SCargoModel",
            targets: ["SCargoModel"]
        ),
        .library(
            name: "RiemLattice",
            targets: ["RiemLattice"]
        ),
        .library(
            name: "SchwartzZippel",
            targets: ["SchwartzZippel"]
        ),
        .library(
            name: "SCargoSweep",
            targets: ["SCargoSweep"]
        ),
        .executable(
            name: "scargo-audit",
            targets: ["scargo-audit"]
        ),
        .executable(
            name: "scargo-riem-lattice",
            targets: ["scargo-riem-lattice"]
        ),
        .executable(
            name: "scargo-schwartz-zippel",
            targets: ["scargo-schwartz-zippel"]
        ),
        .executable(
            name: "scargo-sweep",
            targets: ["scargo-sweep"]
        )
    ],
    targets: [
        .target(
            name: "SCargoModel",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .target(
            name: "RiemLattice",
            dependencies: ["SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .target(
            name: "SchwartzZippel",
            dependencies: ["SCargoModel", "RiemLattice"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .target(
            name: "SCargoSweep",
            dependencies: ["SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "scargo-audit",
            dependencies: ["SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "scargo-riem-lattice",
            dependencies: ["RiemLattice", "SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "scargo-schwartz-zippel",
            dependencies: ["SchwartzZippel", "SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "scargo-sweep",
            dependencies: ["SCargoSweep", "SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "SCargoModelTests",
            dependencies: ["SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "RiemLatticeTests",
            dependencies: ["RiemLattice", "SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "SchwartzZippelTests",
            dependencies: ["SchwartzZippel", "SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "SCargoSweepTests",
            dependencies: ["SCargoSweep", "SCargoModel"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        )
    ]
)
