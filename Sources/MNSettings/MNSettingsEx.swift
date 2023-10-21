//
//  File.swift
//  
//
//  Created by Ido on 16/08/2023.
//

import Foundation
import DSLogger
import MNUtils

#if VAPOR
import Vapor
#endif

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettingsEx")?.setting(verbose: true)
