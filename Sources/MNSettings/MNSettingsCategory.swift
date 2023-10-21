//
//  MNSettingsCategory.swift
//  
//
//  Created by Ido on 15/08/2023.
//

import Foundation
import DSLogger
import MNUtils

#if VAPOR
import Vapor
#endif

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettingsCategory")?.setting(verbose: false)


/// A settings category - may contain other settings categories (nesting). It is intended to contain MNSettable property wrappers. Will registers and validate all names/keys of all MNettable properties:
///
public class MNSettingsCategory { // : CustomDebugStringConvertible
    // MARK: Const
    // MARK: Static
    public static let MAX_NESTING_LEVEL = 6
    
    // MARK: Properties / members
    private (set) public weak var settings : MNSettings? = nil
    private (set) var categoryName : MNSCategoryName = "?"
    private (set) var nestingLevel : Int = 0
    private (set) var subSettings : [Weak<MNSettingsCategory>]? = nil
    private (set) public weak var parent : MNSettingsCategory? = nil
    
    // MARK: Lifecycle
    init(settings:MNSettings? = MNSettings.standard, customName:String? = nil) {
        var custmName = customName
        if let custmName = custmName {
            if custmName.count < 2 {
                dlog?.warning("MNSettingsCategory(settings:customName:) customName [\(custmName)] is too small!")
            }
        }
        if custmName == MNSettings.OTHER_CATERGORY_NAME && "\(type(of: self))" != MNSettings.OTHER_CATERGORY_CLASS_NAME {
            custmName = MNSettings.OTHER_CATERGORY_NAME.trimmingCharacters(in: .punctuationCharacters) + "\(Date.now.timeIntervalSince1970)"
            dlog?.warning("MNSettingsCategory(settings:customName:) customName [\(MNSettings.OTHER_CATERGORY_NAME)] is a reserved name! -- all MNSettables / values / keys will be registered inside the internal (existing) \"other\" category instance!")
        }
        
        self.categoryName = customName ?? MNSettings.sanitizeString("\(Self.self)")
        self.settings = settings
        // will check if self is not a child of other category and register the categories into the tree.
        self.registerCategories(isBoot: true)
        MNExec.exec(afterDelay: 0.01) {[self] in
            self.validateCaterogyTree(isLog: dlog?.isVerboseActive ?? false)
            // After all registerCategories of all Categories/Classes is done (whereby each category inherits the correct settings instance)
            // We register the actual settings / properties in each category to the correct settings
            self.registerSettableProperties(isBoot: true)
        }
    }
    
    deinit {
        dlog?.note("deinit \(self.categoryName)")
    }
    
    // MARK: Private
    private func invalidateCategoryName() {
        var str = self.parentCategoryNames.joined(separator: MNSettings.CATEGORY_DELIMITER) //  + "\(Self.self)"
        str = MNSettings.sanitizeString(str)
        if categoryName != str {
            dlog?.verbose("invalidateCategoryName set new name: \(categoryName) => \(str)")
            categoryName = str
            
        }
    }
    
    private func invalidateSubsettings() {
        self.subSettings = self.subSettings?.filter({ weak in
            weak.value != nil
        })
    }
    
    private func registerCategories(isBoot:Bool, depth:Int = 0) {

        guard self.subSettings == nil else {
            return
        }
        
        guard depth <= Self.MAX_NESTING_LEVEL else {
            dlog?.warning("registerCategories \(Self.self) encountered nesting level > \(Self.MAX_NESTING_LEVEL) (MAX_NESTING_LEVEL)")
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
                    dlog?.success("changing settings for: [\(val.categoryName)] to: [\(sett.name)]")
                    val.settings = sett
                    sett.registerCategory(val)
                }
                
                return Weak(value: val)
            }
            return nil
        })
        
        dlog?.verbose(log:.success, "\(self.debugDescription) registerCategories (found: \(self.subSettings?.count ?? 0) FOR DEPTH: \(depth + 1))")
        for sub in subSettings ?? [] {
            if let sub = sub.value {
                sub.registerCategories(isBoot:isBoot, depth: depth + 1)
            }
        }
        
        // Register:
        MNExec.exec(afterDelay: 0.0) {[self, settings] in
            dlog?.verbose("\(self.debugDescription) nl:\(self.nestingLevel) Will register into setting: \(settings?.name ?? "<nil>")")
            if self.nestingLevel == 0 {
                self.recourseDownTree { cat in
                    cat.settings = self.settings
                }
                settings?.registerCategory(self)
            }
        }
    }
    
    // MARK: Public
    
    var isCanRecourse : Bool {
        guard self.settings != nil else {
            dlog?.note("\(self.debugDescription).isCanRecourse failed: no settings!")
            return false
        }
        
        guard self.nestingLevel <= Self.MAX_NESTING_LEVEL else {
            dlog?.note("\(self.debugDescription).isCanRecourse failed: top nesting level reached: MAX_NESTING_LEVEL")
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
            dlog?.info(tab + ctx + " recourseDownTree")
        }

        // clean Subsettings from weak elements that were released:
        self.invalidateSubsettings()
        
        if let subSettings = self.subSettings, subSettings.count > 0 {
            for weak in subSettings {
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
        return (self.subSettings?.count ?? 0) == 0
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
            let cnt =  cat.subSettings?.count ?? 0
            let sign = (cnt > 0 || cat.nestingLevel == 0) ? "+ " : ("  - ")
            dlog?.info(tab + sign + cat.debugDescription + " has \(cnt) sub-categories.")
        }
    }

    public func validateCaterogyTree(isLog:Bool) {
        if self.nestingLevel == 0, self.subSettings?.count ?? 0 > 0, self.parent == nil {
            self.recourseDownTree { cat in
                let tab = "   ".repeated(times: cat.nestingLevel)
                if let parent = cat.parent, parent.settings != cat.settings {
                    cat.settings = parent.settings
                }
                let prefix = cat.parentCategoryNames.joined(separator: MNSettings.CATEGORY_DELIMITER)
                if !cat.categoryName.hasPrefix(prefix) {
                    dlog?.note("Category name: [\(cat.categoryName)] should have the prefix: \(prefix)")
                }
                
                if isLog && MNUtils.debug.IS_DEBUG == true && dlog?.isVerboseActive ?? false {
                    dlog?.info("validateCaterogyTree: \(tab) [\(cat.categoryName)] level:\(cat.nestingLevel) settings: [\(cat.settings?.name ?? "<nil>" )] parent: [\(cat.parent?.categoryName ?? "<nil>" )]")
                }
            }
        }
    }
    
    private func validatePropertyKey() {
        
    }
    
    public func registerSettableProperties(isBoot:Bool = false) {
        
        // Validate the settings are ok downtree: JIC
        let root = self.rootCategory
        guard let settings = root.settings else {
            dlog?.warning(" registerSettableProperties category: [\(root.categoryName)] cannot occur without a settings (currently <nil>)")
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
    }

}
