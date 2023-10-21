//
//  MNUserDefaultsPersistor.swift
//  
//
//  Created by Ido on 08/08/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNUserDefaultsPersistor")?.setting(verbose: false)

// DO NOT: MNSettingSaveLoadable

public class MNUserDefaultsPersistor : MNSettingsPersistor {

    weak private var _instance : UserDefaults?
    
    // Most commonly use init(.standard) to reference UserDefaults.standard
    init(_ instance: UserDefaults) {
        _instance = instance
    }
    
    static var standard : MNUserDefaultsPersistor = MNUserDefaultsPersistor.init(.standard)

    // MARK: MNSettingsPersistor
    public func setValue<V:MNSettableValue>(_ value:V, forKey key:String) throws {
        guard let instance = _instance else {
            let msg = "setValue \(value) forKey: \(key). \"instance\" does not exist!"
            dlog?.note(msg)
            throw MNError(code: .misc_failed_updating, reason: msg)
        }

        instance.setValue(value, forKey: key)
    }

    public func setValuesForKeys(dict: [MNSKey : AnyMNSettableValue]) throws {
        guard let instance = _instance else {
            let msg = "setValuesForKeys \(dict.keys.descriptionJoined). \"instance\" does not exist!"
            dlog?.note(msg)
            throw MNError(code: .misc_failed_updating, reason: msg)
        }

        dlog?.verbose(">>[5]a    setValuesForKeys: \(dict)")
        for (key, val) in dict {
            instance.setValue(val, forKey: key)
        }
    }

    public func setAllValuesForKeys(dict: [MNSKey : AnyMNSettableValue]) async throws {
        let keys = _instance?.dictionaryRepresentation().keysArray
        let keysToRemove = keys?.removing(objects: dict.keysArray)
        for k in keysToRemove ?? [] {
            _instance?.setNilValueForKey(k)
        }
        try self.setValuesForKeys(dict: dict)
    }
    
    public func fetchValues<V>(forKeys keys: [MNSKey]) async throws -> [MNSKey : V]? where V : CustomStringConvertible, V : Decodable, V : Encodable, V : Hashable {
        var result : [MNSKey : V] = [:]
        for (k, v) in _instance?.dictionaryWithValues(forKeys: keys) ?? [:] {
            let key = (k as MNSKey)
            if let value = v as? V {
                result[key] = value
            }
        }
        return result
    }
    
    public func fetchValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V? {
        guard let instance = _instance else {
            dlog?.note("value forKey: \(key). instance does not exist!")
            return nil
        }

        return instance.value(forKey: key) as? V
    }

    public func keyWasChanged(from fromKey: MNSKey,
                              to toKey: MNSKey,
                              value: AnyMNSettableValue,
                              context: String,
                              caller:Any?) {
        guard let instance = _instance else {
            dlog?.note("keyWasChanged forKey: \(fromKey) => \(toKey) instance does not exist! (\(context))")
            return
        }

        instance.setValue(nil, forKey: fromKey)
        instance.setValue(value, forKey: toKey)
        dlog?.verbose("keyWasChanged from: \(fromKey) to: \(toKey) (\(context))")
    }

    public func valueWasChanged(key: MNSKey,
                                from fromValue: AnyMNSettableValue,
                                to toValue: AnyMNSettableValue,
                                context: String,
                                caller:Any?) {
        guard let instance = _instance else {
            dlog?.note("valueWasChanged  from: \(fromValue) to: \(toValue)  \(key) instance does not exist! (\(context))")
            return
        }

        let prev = instance.value(forKey: key) as? AnyHashable
        if prev?.hashValue != fromValue.hashValue {
            instance.setValue(toValue, forKey: key)
        } else if prev?.hashValue != toValue.hashValue {
            dlog?.verbose(log: .fail, "\(Self.self) valueWasChanged for key: \(key) did not need to change value - new value was already set! \(toValue)")
        } else {
            instance.setValue(toValue, forKey: key)
        }


        dlog?.verbose("valueWasChanged for: \(key) from: \(fromValue) to: \(toValue) context: \(context)")
    }
    
    // TODO: Should we register all default values ?
    // instance.register(defaults: [String : Any])
}

