//
//  Version.swift
//
//
//  Created by Ido on 21/10/2023.
//

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
let MNSETTINGS_BUILD_NR : Int = 4
let MNSETTINGS_BUILD_VERSION = MNSemver (
    major: 0,
    minor: 1,
    patch: 0,
    prerelease: "\(PreRelease.alpha.rawValue)",
    metadata: [String(format: "%04X", MNSETTINGS_BUILD_NR)]
)
