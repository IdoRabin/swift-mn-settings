//
//  MNSettingsMgr.swift
//
//
//  Created by Ido on 31/10/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettingsMgr")?.setting(verbose: true)


struct MNSettingsMgrConfig {
    let isCreateDefaultSettingsSingleton : Bool
    
    static var `default` : MNSettingsMgrConfig {
        return MNSettingsMgrConfig(isCreateDefaultSettingsSingleton: false)
    }
}

class MNSettingsMgr {
    class MNDefaultSettings : MNSettings {
    }
    
    private var instances : [MNSKey:Weak<MNSettings>] = [:]
    private var registerWaitlist : [Weak<MNSettingsElement>] = []
    
    // MARK: Singleton
    private let config : MNSettingsMgrConfig!
    var _defaultInstanceKey : MNSKey? = nil
    var _defaultInstance : MNDefaultSettings? = nil
    
    public static let shared = MNSettingsMgr()
    private init(config : MNSettingsMgrConfig = MNSettingsMgrConfig.default) {
        self.config = config
        MNExec.exec(afterDelay: 0.01) {[weak self] in
            dlog?.info("Will construct")
            for (_, instance) in self?.instances ?? [:] {
                instance.value?.construct()
            }
        }
    }
    
    @discardableResult
    func registerIfNeeded(instance : MNSettings)->Bool {
        let key = instance.key
        guard self.instance(byKey: key) !== instance else {
            // Exactly the same instance already exists!
            return false
        }
        
        if let existing = self.instance(byKey: key), existing == instance {
            dlog?.verbose(log: .note, "registerIfNeeded for: [\(key)] will override / update the existing instance. from:\(existing) to:\(instance)")
        }
        
        self.instances[key] = Weak(value:instance)
        dlog?.verbose("registerIfNeeded now \(self.instances.count) instances. addeed: \(instance)")
        return true
    }
    
    func hasInstance(byKey key:MNSKey)->Bool {
        return self.instance(byKey: key) != nil
    }
    
    func instance(byKey key:MNSKey)->MNSettings? {
        
        // Use root key in delimited keypath
        let comps = key.components(separatedBy: MNSettingsElement.KEYS_DELIMITER)
        if let first = comps.first, let instance = self.instances[first]?.value {
            return instance
        }
        
        return nil
    }
    
    var defaultInstanceKey : MNSKey? {
        if let defaultKey = self._defaultInstanceKey ?? instances.keys.sorted().first {
            return defaultKey
        }
        return nil
    }
    
    var defaultInstance : MNSettings? {
        if let defaultKey = self.defaultInstanceKey {
            return instance(byKey: defaultKey)
        }
        
        if config.isCreateDefaultSettingsSingleton && self._defaultInstance == nil {
            let newDefault = MNDefaultSettings()
            self._defaultInstance = newDefault
            self._defaultInstanceKey = newDefault.key
            return newDefault
        }
        
        return nil
    }
    
    func isDefaultInstance(byKey: MNSKey) -> Bool {
        return byKey == self.defaultInstanceKey
    }
    
    func isDefaultInstance(_ instance:MNSettings) -> Bool {
        return instance.key == self.defaultInstanceKey
    }
    
    private func internal_addToRegisterWaitlist(_ elems: [MNSettingsElement]) {
        self.cleanupRegisterWaitlist()
        let registeredFullKeys = registerWaitlist.values.map { $0.keysPathAsFullKey}
        let toAdd = elems.filter { elem in
            !registeredFullKeys.contains(elem.keysPathAsFullKey)
        }
        guard toAdd.count > 0 else {
            return
        }
        
        dlog?.info("addToRegisterWaitlist \(toAdd.keys.descriptionsJoined)")
        registerWaitlist.append(contentsOf: toAdd.map{ Weak(value: $0)})
    }
    
    func addToRegisterWaitlist(_ elems: [MNSettingsElement]) {
        self.internal_addToRegisterWaitlist(elems)
    }
    
    func addToRegisterWaitlist(_ elem: MNSettingsElement) {
        self.addToRegisterWaitlist([elem])
    }
    
    func cleanupRegisterWaitlist() {
        registerWaitlist.removeAll { weakWrapper in
            switch weakWrapper.value {
            case .none:
                // weak wrapped an instance that was released
                return true
            case .some(let val):
                if val.parent != nil {
                    // weak wrapped an instance that waas assigned a parent
                    return true
                } else if (val as? MNSettings)?.isRegistered == true {
                    // weak wrapper for a settings
                    return true
                }
                return false
            }
        }
    }
    
    func removeFromRegisterWaitlist(_ elems: [MNSettingsElement]) {
        self.cleanupRegisterWaitlist()
        let allFullKeys = elems.compactMap { $0.keysPathAsFullKey }
        registerWaitlist.removeAll { weakWrapper in
            weakWrapper.value == nil || allFullKeys.contains(elementEqualTo: weakWrapper.value?.keysPathAsFullKey ?? "")
        }
    }
    
    func removeFromRegisterWaitlist(_ elem: MNSettingsElement) {
        self.removeFromRegisterWaitlist([elem])
    }
}
