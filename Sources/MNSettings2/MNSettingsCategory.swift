//
//  MNSettingsCategory.swift
//
//
//  Created by Ido on 31/10/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettingsCategory")?.setting(verbose: true)

class MNSettingsCategory : MNSettingsElement {
    
    private func findBestSettings()->MNSettings? {
        dlog?.info("findBestSettings for: \(self.key) : \(Self.self)")
        
        var result : MNSettings? = nil
        let path = self.key.components(separatedBy: MNSettingsElement.KEYS_DELIMITER)
        var accum : [MNSKey] = []
        for key in path {
            accum.append(key)
            let possibleKeys = [key, accum.joined(separator: MNSettingsElement.KEYS_DELIMITER)]
            for pkey in possibleKeys {
                if let ainstance = MNSettingsMgr.shared.instance(byKey: pkey) {
                    result = ainstance
                    break
                }
            }
            if result != nil {
                break
            }
        }
        
        if result == nil, let defInstance = MNSettingsMgr.shared.defaultInstance {
            dlog?.note("using defaultInstance: \(defInstance.key) for category: \(self)")
            result = defInstance
        }
        return result
    }
    
    override func registerIfNeeded() {
        
        let logPrfx = "[\(self.key)]"
        if self.parentKeys == nil {
            let path = "\(Self.self)".components(separatedBy: MNSettingsElement.KEYS_DELIMITER)
            if path.count > 0 {
                var accum : [MNSKey] = []
                for key in path {
                    accum.append(key)
                    var possibleKeys = [key]
                    if accum.count > 1 {
                        possibleKeys.append(accum.joined(separator: MNSettingsElement.KEYS_DELIMITER))
                    }
                    for pkey in possibleKeys.uniqueElements() {
                        if let ainstance = MNSettingsMgr.shared.instance(byKey: pkey) {
                            ainstance.addChildren([self])
                            self.parentKeys = path
                        }
                    }
                }
            }
        }
        
        let settingsKey = self.parentKeys?.first ?? MNSettingsMgr.shared.defaultInstanceKey
        if let settingsKey = settingsKey, self.parentKeys?.count ?? 0 > 0, let settingsInstance = MNSettingsMgr.shared.instance(byKey: settingsKey) {
            settingsInstance.addChildren([self])
            dlog?.info("\(logPrfx) registerIfNeeded for: \(self.key) : \(Self.self) settingsKey: \(settingsKey)")
        } else {
            MNSettingsMgr.shared.addToRegisterWaitlist([self])
        }
    }
}
