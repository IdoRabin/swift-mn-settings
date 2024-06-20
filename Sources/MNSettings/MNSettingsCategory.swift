//
//  MNSettingsCategory.swift
//  
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation
import Logging
import MNUtils

#if VAPOR
import Vapor
#endif

fileprivate let dlog : Logger? = Logger(label: "MNSettingsCategory") // DLog.forClass("MNSettingsCategory")?.setting(verbose: false)

protocol MNSettingsCategoryRegistrable {
    func registerSettableProperties(isBoot:Bool)
    func registerCategories(isBoot:Bool)
}

/// A settings category - may contain other settings categories (nesting). It is intended to contain MNSettable property wrappers. Will registers and validate all names/keys of all MNettable properties:
///
open class MNSettingsCategory { // : CustomDebugStringConvertible
    // MARK: Const
    // MARK: Static
    public static let MAX_NESTING_LEVEL = 6
    
    // MARK: Properties / members
    internal (set) public weak var settings : MNSettings? = nil
    var categoryName : MNSCategoryName = "?" {
        didSet {
            if self.categoryName.contains("AppPrefillData") {
                dlog?.info("categoryName AppPrefillData!")
            }
        }
    }
    var nestingLevel : Int = 0
    var subCategories : [Weak<MNSettingsCategory>]? = nil
    internal (set) public weak var parent : MNSettingsCategory? = nil
    
    // MARK: Lifecycle
    public init(settings:MNSettings? = MNSettings.implicit ?? MNSettings.standard, customName:String? = nil) {
        var custmName = customName
        if let cstName = custmName {
            custmName = MNSettings.sanitizeString(cstName)
            if cstName.count < 2 {
                dlog?.warning("MNSettingsCategory(settings:customName:) customName [\(cstName)] is too small!")
            }
            if cstName == MNSettings.OTHER_CATERGORY_NAME && "\(type(of: self))" != MNSettings.OTHER_CATERGORY_CLASS_NAME {
                custmName = MNSettings.OTHER_CATERGORY_NAME.trimmingCharacters(in: .punctuationCharacters) + "\(Date.now.timeIntervalSince1970)"
                dlog?.warning("MNSettingsCategory(settings:customName:) customName [\(MNSettings.OTHER_CATERGORY_NAME)] is a reserved name! -- all MNSettables / values / keys will be registered inside the internal (existing) \"other\" category instance!")
            }
        }
        
        dlog?.verbose("init(settingsNamed: \(settings?.name ?? "<unknown>") customName: \(customName.descOrNil)")
        self.categoryName = customName ?? MNSettings.sanitizeString("\(Self.self)")
        self.settings = settings
        // will check if self is not a child of other category and register the categories into the tree.
        MNExec.exec(afterDelay: 0.01) {[self] in
            
            self.validateCaterogyTree(isLog: dlog?.isVerboseActive ?? false)
            // After all registerCategories of all Categories/Classes is done (whereby each category inherits the correct settings instance)
            // We register the actual settings / properties in each category to the correct settings
            self.registerSettableProperties(isBoot: true)
        }
    }
    
    public convenience init(settingsNamed:String, customName:String? = nil) {
        if let settings = MNSettings.instance(byName: settingsNamed) {
            self.init(settings: settings, customName: customName)
        } else {
            self.init(customName:customName)
        }
    }
    
    deinit {
        dlog?.notice("deinit \(self.categoryName)")
    }
    
    // MARK: Private
    internal func invalidateCategoryName() {
        var str = self.parentCategoryNames.joined(separator: MNSettings.CATEGORY_DELIMITER) //  + "\(Self.self)"
        str = MNSettings.sanitizeString(str)
        if categoryName != str {
            dlog?.verbose("invalidateCategoryName set new name: \(categoryName) => \(str)")
            categoryName = str
            
        }
    }
    
    private func invalidateSubsettings() {
        self.subCategories = self.subCategories?.filter({ weak in
            weak.value != nil
        })
    }
    
    // MARK: Public
    
    var isCanRecourse : Bool {
        guard self.settings != nil else {
            dlog?.notice("\(self.debugDescription).isCanRecourse failed: no settings!")
            return false
        }
        
        guard self.nestingLevel <= Self.MAX_NESTING_LEVEL else {
            dlog?.notice("\(self.debugDescription).isCanRecourse failed: top nesting level reached: MAX_NESTING_LEVEL")
            return false
        }
        
        return true
    }
    
    func iterateUpTree(_ block:(_ cat:MNSettingsCategory)->Void, depth:Int = 0) {
        guard depth <= Self.MAX_NESTING_LEVEL else {
            dlog?.warning("\(self.debugDescription).recourse(...) exceeded recursion nesting level! \(Self.MAX_NESTING_LEVEL)")
            return
        }
        
        // NOTE: Depth does not equal the category's nestingLevel!
        // Perform on self
        block(self)
        
        if let parent = self.parent {
            parent.iterateUpTree(block, depth: depth + 1)
        }
    }
    
    func recourseDownTree(_ block:(_ cat:MNSettingsCategory)->Void, depth:Int = 0) {
        // NOTE: depth-first downtree recursion
        // NOTE: Depth does not neccesarily mean the category's nestingLevel, for instance, starting a recoursion not on the tree top, bu in a branch...
        guard depth <= Self.MAX_NESTING_LEVEL else {
            dlog?.warning("\(self.debugDescription).recourse(...) exceeded recursion nesting level! \(Self.MAX_NESTING_LEVEL)")
            return
        }
        
        // Perform on self
        block(self)
        
        // Can check children and recourse
        guard self.isCanRecourse else {
            return
        }
        
        if false && MNUtils.debug.IS_DEBUG {
            let tab = "  ".repeated(times: self.nestingLevel)
            let ctx = self.debugDescription
            dlog?.info("\(tab + ctx) recourseDownTree")
        }

        // clean Subsettings from weak elements that were released:
        self.invalidateSubsettings()
        
        if let subCategories = self.subCategories, subCategories.count > 0 {
            for weak in subCategories {
                if let sub = weak.value {
                    sub.recourseDownTree(block, depth: depth + 1)
                }
            }
        }
    }
    
    // Ordered from root (first) to parent (last)
    var parentCategories : [MNSettingsCategory] {
        var result: [MNSettingsCategory] = []
        iterateUpTree { cat in
            result.insert(cat, at: 0)
        }
        return result
    }
    
    // Ordered from root (first) to parent (last)
    var parentCategoryNames : [MNSCategoryName] {
        return parentCategories.map { $0.categoryName.components(separatedBy: MNSettings.CATEGORY_DELIMITER).last! }
    }
    
    var rootCategory : MNSettingsCategory {
        var ref = self
        
        // Secure the while loop
        var counter : Int = MNSettingsCategory.MAX_NESTING_LEVEL + 2
        
        while ref.parent != nil && counter > 0 {
            // dlog?.info("While: \(ref.categoryName)")
            if let prnt = ref.parent {
                ref = prnt
            } else {
                break
            }
            counter -= 1
        }
        return ref
    }
    
    var isRootCategory : Bool {
        return self.parent == nil
    }
    
    var isLeafCategory : Bool {
        return (self.subCategories?.count ?? 0) == 0
    }
    
    var isBranchCategory : Bool {
        return !self.isRootCategory && !self.isLeafCategory
    }
    
    // CustomDebugStringConvertible
    public var debugDescription: String {
        if self.categoryName == MNSettings.OTHER_CATERGORY_NAME && "\(Self.self)" == MNSettings.OTHER_CATERGORY_CLASS_NAME {
            return "<\(Self.self) *\(self.categoryName)* nesting depth: (\(self.nestingLevel))>"
        } else {
            return "<\(Self.self) name: [\(self.categoryName)] nesting depth: (\(self.nestingLevel))>"
        }
    }

    // MARK: Recoursive funcs:
    public func logTree(depth:Int? = nil) {
        let depth = depth ?? self.nestingLevel
        guard depth <= Self.MAX_NESTING_LEVEL else {
            dlog?.warning("\(self.debugDescription).recourse(...) exceeded recursion nesting level! \(Self.MAX_NESTING_LEVEL)")
            return
        }
        
        self.recourseDownTree { cat in
            let tab = "  ".repeated(times: depth)
            let cnt =  cat.subCategories?.count ?? 0
            let sign = (cnt > 0 || cat.nestingLevel == 0) ? "+ " : ("  - ")
            dlog?.info("\(tab + sign + cat.debugDescription) has \(cnt) sub-categories.")
        }
    }

    public func validateCaterogyTree(isLog:Bool) {
        if self.nestingLevel == 0, self.subCategories?.count ?? 0 > 0, self.parent == nil {
            self.recourseDownTree { cat in
                let tab = "   ".repeated(times: cat.nestingLevel)
                if let parent = cat.parent, parent.settings != cat.settings {
                    cat.settings = parent.settings
                }
                let prefix = cat.parentCategoryNames.joined(separator: MNSettings.CATEGORY_DELIMITER)
                if !cat.categoryName.hasPrefix(prefix) {
                    dlog?.notice("Category name: [\(cat.categoryName)] should have the prefix: \(prefix)")
                }
                
                if isLog && MNUtils.debug.IS_DEBUG == true && dlog?.isVerboseActive ?? false {
                    dlog?.info("validateCaterogyTree: \(tab) [\(cat.categoryName)] level:\(cat.nestingLevel) settings: [\(cat.settings?.name ?? "<nil>" )] parent: [\(cat.parent?.categoryName ?? "<nil>" )]")
                }
            }
        }
    }

}
