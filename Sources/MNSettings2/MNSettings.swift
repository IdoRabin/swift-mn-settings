//
//  MNSettings.swift
//
//
//  Created by Ido on 31/10/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettings")?.setting(verbose: true)

struct MNSettingConfig {
    let isAddSettingsPrefix : Bool
    
    static var `default` : MNSettingConfig {
        return MNSettingConfig(isAddSettingsPrefix: true)
    }
}

class MNSettings : MNSettingsElement, CustomStringConvertible {
    // MARK: Types
    // MARK: Const
    // MARK: Static
    // MARK: Properties / members
    var bootState: MNBootState = .unbooted
    override var parentKeys : [MNSKey]? {
        get {
            return nil
        }
        set {
            dlog?.verbose(log: .note, " KEY: \(key) cannot set a parent keys! (parentKeys setter)")
        }
    }
    
    override var parent: Weak<MNSettingsElement>? {
        get {
            return nil
        }
        set {
            dlog?.verbose(log: .note, " KEY: \(key) cannot set a parent! (parent setter)")
        }
    }
    
    var isDefault : Bool {
        return MNSettingsMgr.shared.isDefaultInstance(byKey: self.key)
    }
    
    var isRegistered : Bool {
        return MNSettingsMgr.shared.hasInstance(byKey: self.key)
    }
    
    static var `default` : MNSettings? {
        return MNSettingsMgr.shared.defaultInstance
    }
    
    // MARK: CustomStringConvertible
    var description: String {
        return "<\(Self.self) key:\"\(self.key)\" state: \(self.bootState) \(self.isDefault ? "DEFAULT" : "")>"
    }
    
    // MARK: Private
    // MARK: Lifecycle
    init(key:MNSKey? = nil) {
        super.init(key: key)
        self.findChildCategories()
        Task {
            do {
                try await self.load()
            } catch let error {
                dlog?.warning("[\(self.key)] loading failed: \(error.description)")
            }
            
            self.bootState = .booting
        }
    }
    
    func load() async throws {
        let prevState = self.bootState
        self.bootState = .loading
        let delay = UInt64(0.5 * 1_000_000_000)
        try await Task.sleep(nanoseconds: delay)
        self.bootState = prevState
    }
    
    func findChildCategories() {
        let mirror = Mirror(reflecting: self)
        
        var toAdd : [MNSettingsCategory] = []
        
        // Find subclass instances:
        for (k, v) in mirror.children {
            if let cat = v as? MNSettingsCategory {
                // dlog?.verbose("k:\(k.descOrNil) v:\(cat)")
                if !self.hasChild(cat) {
                    toAdd.append(cat)
                }
            } else if let cat = v as? MNSettingsCategory?, let cat = cat {
                //dlog?.verbose("k:\(k.descOrNil) v:\(cat)")
                if !self.hasChild(cat) {
                    toAdd.append(cat)
                }
            } else {
                let atype = type(of:v)
                if let elem = v as? MNSettingsCategory?, elem == .none {
                    dlog?.info("Optional \(k.descOrNil) will be a category. \(atype)")
                } else {
                    dlog?.verbose(log:.fail, "k: \(k.descOrNil) v: \(v) NOT a category / not initialized!")
                }
            }
        }
        
        // Was found
        self.addChildren(toAdd)
    }
    
    override func registerIfNeeded() {
        // caled from super.init..
        
        // Regiter self instance
        MNSettingsMgr.shared.registerIfNeeded(instance: self)
    }
    
    required init(from decoder: Decoder) throws {
        self.bootState = .loading
        try super.init(from: decoder)
        self.bootState = .running
    }
    
    override func encode(to encoder: Encoder) throws {
        dlog?.todo("implement encode(to encoder:..)")
    }
    
    override func addChildren(_ childs : [MNSettingsElement]) {
        let categories : [MNSettingsCategory] = childs.compactMap { elem in
            elem as? MNSettingsCategory }
        
        if categories.count > 0 {
            super.addChildren(categories)
            dlog?.info("addChildren added \(categories.count) categories: \(categories.keys.descriptionsJoined) total: \((self.children?.count).descOrNil) cats.")
        }
        
        let settables : [Any] = childs.compactMap { elem in
            if let settableBase = elem as? any MNSettableValueContainer {
                dlog?.todo("addChildren found MNSettableValueContainer: \(settableBase)")
//                if let settable = settableBase as? MNSettable<settableBase.valueType> {
//                    
//                }
            }
            return nil
        }
        if settables.count > 0 {
            dlog?.todo("addChildren added \(settables.count) settables: \(settables.descriptionJoined) IMPLEMENT REGISTERING SETTABLES")
        }
    }
    
    // MARK: Public
    func setAsDefault() {
        MNSettingsMgr.shared._defaultInstanceKey = self.key
    }
    
    func construct() {
        Task {
            dlog?.info("[\(self.key)] constructing state: \(bootState)")
            self.findChildCategories() // again, for late initialized categories and such
            MNExec.waitFor("MNSettings.\(self.key).contructing wait for loading:", test: {
                ![.loading, .unbooted].contains(self.bootState)
            }, interval: 0.2, timeout: 4) { waitResult in
                switch waitResult {
                case .success:
                    dlog?.todo("constructing: load has completed")
                case .timeout:
                    dlog?.warning("constructing timed out while still loading")
                case .canceled:
                    dlog?.warning("constructing was canceled")
                }
            }
        }
    }
}


