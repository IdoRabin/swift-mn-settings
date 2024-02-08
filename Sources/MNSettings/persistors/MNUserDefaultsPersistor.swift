//
//  MNUserDefaultsPersistor.swift
//  
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation
import Logging
import MNUtils

fileprivate let dlog : Logger? = Logger(label: "MNUserDefaultsPersistor")

// DO NOT: MNSettingSaveLoadable



public class MNUserDefaultsPersistor : MNSettingsPersistor {
    static let DEBUG_CLEAR_ALL = MNUtils.debug.IS_DEBUG && false
    public static let MNUserDefaultsPersistor_Default_KEY_PREFIX : String = "MN."
    
    weak private var _udInstance : UserDefaults?
    weak public var defaultsInstance : UserDefaults? {
        get {
            return _udInstance
        }
    }
    // Most commonly use init(.standard) to reference UserDefaults.standard
    public init(_ instance: UserDefaults = .standard, keyPrefix:String = MNUserDefaultsPersistor_Default_KEY_PREFIX) {
        self._udInstance = instance
        self.debugClearAllIfNeeded() // only in Debug mode and flag is on
        self.keyPrefix = keyPrefix
    }
    
    static var standard : MNUserDefaultsPersistor = MNUserDefaultsPersistor.init(.standard)
    public var keyPrefix = MNUserDefaultsPersistor_Default_KEY_PREFIX
    
    // MARK: MNSettingsPersistor
    fileprivate func prefixKey(_ key:String)->String {
        var result = key
        if !result.hasPrefix(keyPrefix) {
            result = self.keyPrefix + MNSettings.sanitizeString(key)
        }
        return result
    }
    
    func debugClearAllIfNeeded() {
        guard Self.DEBUG_CLEAR_ALL else {
            return
        }
        dlog?.notice("clearAllIfNeeded (clearing all settings)")
        
        if let dict = _udInstance?.dictionaryRepresentation() {
            for (k, _) in dict {
                if k.hasPrefix(self.keyPrefix) {
                    _udInstance?.removeObject(forKey: k)
                }
            }
        }
    }
    
    public func setValue<V:MNSettableValue>(_ value:V, forKey key:String) throws {
        guard let instance = _udInstance else {
            let msg = "setValue \(value) forKey: \(key). \"instance\" does not exist!"
            dlog?.notice("\(msg)")
            throw MNError(code: .misc_failed_updating, reason: msg)
        }

        let prfxKey = self.prefixKey(key)
        instance.setValue(value, forKey: prfxKey)
    }

    public func setValuesForKeys(dict: [MNSKey : AnyMNSettableValue]) throws {
        guard let instance = _udInstance else {
            let msg = "setValuesForKeys \(dict.keys.descriptionJoined). \"instance\" does not exist!"
            dlog?.notice("\(msg)")
            throw MNError(code: .misc_failed_updating, reason: msg)
        }

        dlog?.trace(">>[5]a    setValuesForKeys: \(dict)")
        for (key, val) in dict {
            let prfxKey = self.prefixKey(key)
            instance.setValue(val, forKey: prfxKey)
        }
    }

    public func setAllValuesForKeys(dict: [MNSKey : AnyMNSettableValue]) async throws {
        let keys = _udInstance?.dictionaryRepresentation().keysArray
        
        // Remove keys belonging to the persistor:
        let keysToRemove = keys?.removing(objects: dict.keysArray.filter({ key in
            key.hasPrefix(self.keyPrefix)
        }))
        for k in keysToRemove ?? [] {
            _udInstance?.setNilValueForKey(k)
        }
        
        try self.setValuesForKeys(dict: dict)
    }
    
    public func fetchValues<V>(forKeys keys: [MNSKey]) async throws -> [MNSKey : V]? where V : CustomStringConvertible, V : Decodable, V : Encodable, V : Hashable {
        var result : [MNSKey : V] = [:]
        let prfKeys = keys.map { self.prefixKey($0) }
        for (k, v) in _udInstance?.dictionaryWithValues(forKeys: prfKeys) ?? [:] {
            let key = (k as MNSKey)
            if let value = v as? V {
                result[key] = value
            }
        }
        return result
    }
    
    public func fetchValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V? {
        guard let instance = _udInstance else {
            dlog?.notice("value forKey: \(key). instance does not exist!")
            return nil
        }

        return instance.value(forKey: self.prefixKey(key)) as? V
    }

    public func keyWasChanged(from fromKey: MNSKey,
                              to toKey: MNSKey,
                              value: AnyMNSettableValue,
                              context: String,
                              caller:Any?) {
        guard let instance = _udInstance else {
            dlog?.notice("keyWasChanged forKey: \(fromKey) => \(toKey) instance does not exist! (\(context))")
            return
        }
        guard fromKey != toKey else {
            return
        }
        
        instance.setValue(nil, forKey: self.prefixKey(fromKey))
        instance.setValue(value, forKey: self.prefixKey(toKey))
        dlog?.trace("keyWasChanged from: \(fromKey) to: \(toKey) (\(context))")
    }

    public func valueWasChanged(key: MNSKey,
                                from fromValue: AnyMNSettableValue,
                                to toValue: AnyMNSettableValue,
                                context: String,
                                caller:Any?) {
        guard let instance = _udInstance else {
            dlog?.notice("valueWasChanged  from: \(fromValue.description) to: \(toValue.description)  \(key) instance does not exist! (\(context))")
            return
        }

        let prefKey = self.prefixKey(key)
        let prev = instance.value(forKey: prefKey) as? AnyHashable
        if prev?.hashValue != fromValue.hashValue {
            instance.setValue(toValue, forKey: prefKey)
        } else if prev?.hashValue != toValue.hashValue {
            dlog?.notice("\(Self.self) valueWasChanged for key: \(key) did not need to change value - new value was already set! \(toValue.description)")
        } else {
            instance.setValue(toValue, forKey: prefKey)
        }


        dlog?.trace("valueWasChanged for: \(key) from: \(fromValue.description) to: \(toValue.description) context: \(context)")
    }
    
    // TODO: Should we register all default values ?
    // instance.register(defaults: [String : Any])
}

