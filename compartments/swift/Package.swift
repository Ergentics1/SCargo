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
        .library(
            name: "SCargoGround",
            targets: ["SCargoGround"]
        ),
        .library(
            name: "SCargoAirlock",
            targets: ["SCargoAirlock"]
        ),
        .library(
            name: "SCargoCensus",
            targets: ["SCargoCensus"]
        ),
        .library(
            name: "SCargoEmit",
            targets: ["SCargoEmit"]
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
        ),
        .executable(
            name: "scargo-ground",
            targets: ["scargo-ground"]
        ),
        .executable(
            name: "scargo-airlock",
            targets: ["scargo-airlock"]
        ),
        .executable(
            name: "scargo-census",
            targets: ["scargo-census"]
        ),
        .executable(
            name: "scargo-emit",
            targets: ["scargo-emit"]
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
        .target(
            name: "SCargoGround",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .target(
            name: "SCargoAirlock",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .target(
            name: "SCargoCensus",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .target(
            name: "SCargoEmit",
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
        .executableTarget(
            name: "scargo-ground",
            dependencies: ["SCargoGround"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "scargo-airlock",
            dependencies: ["SCargoAirlock"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "scargo-census",
            dependencies: ["SCargoCensus"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "scargo-emit",
            dependencies: ["SCargoEmit"],
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
        ),
        .testTarget(
            name: "SCargoGroundTests",
            dependencies: ["SCargoGround"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "SCargoAirlockTests",
            dependencies: ["SCargoAirlock"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "SCargoCensusTests",
            dependencies: ["SCargoCensus"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "SCargoEmitTests",
            dependencies: ["SCargoEmit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .treatAllWarnings(as: .error)
            ]
        )
    ]
)
