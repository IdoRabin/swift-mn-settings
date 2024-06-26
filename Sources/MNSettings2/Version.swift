//
//  Version.swift
//
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation
import MNUtils
import AppKit

enum PreRelease: String {
    case none = ""
    case alpha = "alpha"
    case beta = "beta"
    case RC = "RC"
}

// https://semver.org/
// Swift package PackageDescription also supports Sever2 Version struct defined, but we will be using ver 1.0.0

// Hard coded app version:
let MNSETTINGS_NAME_STR : String = "MNSettings"

// String fields allow only alphanumerics and a hyphen (-)
<<<<<<< HEAD:Sources/MNSettings2/Version.swift
let MNSETTINGS_BUILD_NR : Int = 549
=======
let MNSETTINGS_BUILD_NR : Int = 92
>>>>>>> 4d1594ac075be248f31cb914a0635bea69b10561:Sources/MNSettings/Version.swift
let MNSETTINGS_BUILD_VERSION = MNSemver (
    major: 0,
    minor: 2,
    patch: 0,
    prerelease: "\(PreRelease.alpha.rawValue)",
    metadata: [String(format: "%04X", MNSETTINGS_BUILD_NR)]
)
