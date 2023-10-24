//
//  MNSettings+Reflections.swift
//  bricks_server
//
//  Created by Ido on 23/10/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettings+Reg")?.setting(verbose: false)

extension MNSettings : MNSettingsRegistrable {
    
    public func findAndRegisterChildCategories() {
        let logPrefix = "[\(self.name)] findAndRegisterChildCategories"
        dlog?.verbose("\(logPrefix) START")
        let refChildren = Mirror(reflecting: self).children
        let categoryNames = refChildren.compactMap({ label, value in
            if let val = value as? MNSettingsCategory {
                val.nestingLevel = 0
                if val.settings != self {
                    dlog?.verbose(log: .success, "\(logPrefix) changing settings for: [\(val.categoryName)] to: [\(self.name)]")
                    val.settings = self
                }
                val.invalidateCategoryName()
                self.registerCategory(val)
                return val.categoryName
            }
            return nil
        })
        
        dlog?.verbose("\(logPrefix) END found: \(categoryNames.descriptionsJoined)")
        
    }
    
    public func findAndRegisterChildProperties() {
        let logPrefix = "[\(self.name)] findAndRegisterChildProperties"
        dlog?.verbose("\(logPrefix) START")
        // self.registerSettable()
        dlog?.verbose("\(logPrefix) END")
    }
}
