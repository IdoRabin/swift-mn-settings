//
//  MNSettingsCategory+Reflections.swift
//  
//
//  Created by Ido on 23/10/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettingsCategory+Reg")?.setting(verbose: true)

extension MNSettingsCategory : MNSettingsCategoryRegistrable /* reflections */ {
    
    // MARK: Private 
    private var fullPath : String {
        return "\(self.settings?.name ?? "<Unknown>").\(self.categoryName)"
    }
    private func registerCategories(isBoot:Bool, depth:Int = 0) {
        if depth == 0 {
            dlog?.verbose("\(self.fullPath) registerCategories START")
        }
        
        guard self.subSettings == nil else {
            return
        }
        
        guard depth <= Self.MAX_NESTING_LEVEL else {
            dlog?.warning("\(self.fullPath) registerCategories \(Self.self) encountered nesting level > \(Self.MAX_NESTING_LEVEL) (MAX_NESTING_LEVEL)")
            return
        }

        self.nestingLevel = depth
        let refChildren = Mirror(reflecting: self).children
        self.subSettings = refChildren.compactMap({ label, value in
            if let val = value as? MNSettingsCategory {
                val.parent = self
                val.nestingLevel = depth + 1
                val.invalidateCategoryName()
                if let sett = self.settings {
                    dlog?.success("\(self.fullPath) changing settings for: [\(val.categoryName)] to: [\(sett.name)]")
                    val.settings = sett
                    sett.registerCategory(val)
                }
                
                return Weak(value: val)
            }
            return nil
        })
        
        dlog?.verbose(log:.success, "\(self.fullPath) registerCategories (found: \(self.subSettings?.count ?? 0) FOR DEPTH: \(depth + 1))")
        for sub in subSettings ?? [] {
            if let sub = sub.value {
                sub.registerCategories(isBoot:isBoot, depth: depth + 1)
            }
        }
        
        // Register:
        MNExec.exec(afterDelay: 0.01) {[self, settings] in
            dlog?.verbose("\(self.fullPath) nl:\(self.nestingLevel) Will register into setting: \(settings?.name ?? "<nil>")")
            if self.nestingLevel == 0 {
                self.recourseDownTree { cat in
                    cat.settings = self.settings
                }
                settings?.registerCategory(self)
                dlog?.verbose("\(self.fullPath) registerCategories END")
            }
        }
    }
    
    // MARK: Public
    func registerCategories(isBoot:Bool) {
        self.registerCategories(isBoot: isBoot, depth: 0)
    }
    
    func registerSettableProperties(isBoot:Bool = false) {
        dlog?.verbose("\(self.fullPath) registerSettableProperties START")
        
        // Validate the settings are ok downtree: JIC
        let root = self.rootCategory
        guard let settings = root.settings else {
            dlog?.warning("registerSettableProperties category: [\(root.categoryName)] cannot occur without a settings (currently <nil>)")
            return
        }
        dlog?.verbose("\(root.debugDescription) will registerSettableProperties in \(settings.name)")
        
        // We are assuming at this stage that the nestingLevel is set correctly for all categories in the tree:
        root.recourseDownTree { cat in
            let context = (isBoot ? (MNSettings.BOOT_CONTEXT_SUBSTR + " ") : "") + cat.debugDescription + " validateKeys"
            let tab = "  ".repeated(times: cat.nestingLevel)
            // let delim = MNSettings.CATEGORY_DELIMITER
            cat.invalidateCategoryName()
            
            let refChildren : [any MNSettabled] = Mirror(reflecting: cat).children.compactMap { item in
                return item.value as? any MNSettabled
            }
            dlog?.verbose(tab + "registerSettableProperties in cat: \(tab) [\(cat.categoryName)] has: \(refChildren.count) mirrored child/ren")
          
            // Set child MNSettables to correct keys:
            for refChild in refChildren {
                if refChild.settings != settings {
                    // Set the "settings" instance of the property to the
                    // Will also set observing corretly in the settings and more.
                    refChild.setMNSettings(settings, context: context)
                }
                
                let expectedKeyPrefix = cat.parentCategoryNames.joined(separator: MNSettings.CATEGORY_DELIMITER)
                if !refChild.key.contains(expectedKeyPrefix) {
                    let newKey = expectedKeyPrefix + MNSettings.CATEGORY_DELIMITER + refChild.key
                    do {
                        try refChild.setKey(newKey, context: context)
                    } catch let error {
                        dlog?.note(tab + "validateKeysInCategory failed setKey: \"\(newKey)\" error: \(error.description)")
                    }
                }
                
            }
        }
        
        dlog?.verbose("\(self.fullPath) registerSettableProperties END")
    }

}
