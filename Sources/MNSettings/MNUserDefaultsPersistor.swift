//
//  MNUserDefaultsPersistor.swift
//  
//
//  Created by Ido on 08/08/2023.
//

import Foundation

public class MNUserDefaultsPersistor : MNSettingsPersistor {
    
    
    weak private var _instance : UserDefaults?
    
    // Most commonly use init(.standard) to reference UserDefaults.standard
    init(_ instance: UserDefaults) {
        _instance = instance
    }
    
    static var standard : MNUserDefaultsPersistor = MNUserDefaultsPersistor.init(.standard)
    
    // MARK: MNSettingsPersistor
    public func setValue<V:MNSettableValue>(_ value:V?, forKey key:String) async throws {
        UserDefaults.standard.setValue(value, forKey: key)
    }
    
    public func setValuesForKeys(dict: [MNSKey : any MNSettableValue]) async throws {
        
        for (key, val) in dict {
            UserDefaults.standard.setValue(val, forKey: key)
        }
    }
    
    public func value<V:MNSettableValue>(forKey key:String) async throws -> V? {
        return UserDefaults.standard.value(forKey: key) as? V
    }
    
    // Register all default values
    // UserDefaults.standard.register(defaults: [String : Any])
}
