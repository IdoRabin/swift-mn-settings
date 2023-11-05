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

fileprivate let MAX_CATEGORY_SEARCH_TIMED_RECURSION_DEPTH = 8

extension MNSettings : MNSettingsRegistrable {
    
    private func internal_findAndRegisterChildCategories(depth:Int = 0, onlyWithLabels:[String] = []) {
        let logPrefix = (dlog != nil) ? "[\(self.name)] findAndRegisterChildCategories d:[\(depth)]" : "?"
        if type(of:self) == MNSettings.self {
            return
        }
        
        guard depth < MAX_CATEGORY_SEARCH_TIMED_RECURSION_DEPTH else {
            dlog?.verbose(log:.warning, "internal_\(logPrefix) recursion is too big!")
            return
        }
        
        dlog?.verbose("\(logPrefix) START")
        
        var uninitializedLabels : [String] = []
        let refChildren = Mirror(reflecting: self).children
        
        func registerE(category:MNSettingsCategory) {
            category.nestingLevel = 0
            if category.settings != self {
                dlog?.verbose(log: .success, "\(logPrefix) changing settings for: [\(category.categoryName)] to: [\(self.name)]")
                category.settings = self
            }
            category.invalidateCategoryName()
            self.registerCategory(category)
        }
        
        let categoryNames : [String] = refChildren.compactMap({ label, value in
            if onlyWithLabels.count == 0 || onlyWithLabels.contains(label ?? "?????") {
                if let category = value as? MNSettingsCategory {
                    registerE(category: category)
                    return category.categoryName
                } else if let val = value as? (MNSettingsCategory?), let label = label {
                    switch val {
                    case .none:
                        uninitializedLabels.append(label)
                        let tip = type(of: val)
                    case .some(let category):
                        // Was initialized:
                        registerE(category: category)
                        return category.categoryName
                    }
                }
            }
            return nil
        })
        
        if uninitializedLabels.count > 0 {
            MNExec.exec(afterDelay: max(0.05, 0.05 * Double(depth))) {
                // dlog?.info("will retry [\(self.name)] findAndRegisterChildCategories labels:\(uninitializedLabels.descriptionsJoined)")
                self.internal_findAndRegisterChildCategories(depth: depth + 1, onlyWithLabels:uninitializedLabels)
            }
        }
        dlog?.verbose("\(logPrefix) END found: \(categoryNames.descriptionsJoined)")
    }
    
    
    /// Only for subclasses - will search using reflection properties that are categories.
    public func findAndRegisterChildCategories() {
        internal_findAndRegisterChildCategories()
    }
    
    /// Only for subclasses - will search using reflection properties that are @Settable.
    public func findAndRegisterChildProperties() {
        let logPrefix = (dlog != nil) ? "[\(self.name)] findAndRegisterChildProperties" : "?"
        if type(of:self) == MNSettings.self {
            return
        }
        let context = "\(self.name).findAndRegisterChildCategories"
        
        dlog?.verbose("\(logPrefix) START")
        let refChildren = Mirror(reflecting: self).children
        let foundChildrenPropNames : [String] = refChildren.compactMap({ label, value in
            if let refChild = value as? any MNSettabled {
                if refChild.settings != self {
                    // Set the "settings" instance of the property to the
                    // Will also set observing corretly in the settings and more.
                    refChild.setMNSettings(self, context: context)
                    return refChild.key
                }
            }
            return nil
        })
        
        dlog?.verbose("\(logPrefix) END. found \(foundChildrenPropNames.count) props: \(foundChildrenPropNames.descriptionsJoined)")
    }
}
