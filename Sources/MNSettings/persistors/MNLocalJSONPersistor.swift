//
//  MNLocalJSONPersistor.swift
//  
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation
import MNUtils
import Logging

fileprivate let dlog : Logger? = Logger(label: "MNLocalJSONPersistor")

// DO NOT: MNSettingSaveLoadable
public class MNLocalJSONPersistor : MNSettingsPersistor {

    let cache = MNAutoSavedCache<String, String>(name: "MNLocalJSONPersistor", maxSize: 5000, attemptLoad: .nextRunloop)
    
    // MARK: CustomStringConvertible
    var description: String {
        return "<\(Self.self) cache.name: \(cache.name) >"
    }
    public init(name:String = "", filepath:URL? = nil) {
        if name.count > 0 && name != "\(Self.self)" {
            cache.name = "MNLocalJSONPersistor_\(name)"
            cache.observers.add(observer: self)
        }
    }
    
    private func transformIn<Value>(value:Value, key:String, encoder:JSONEncoder? = nil) throws -> String? {
        var result : String? = nil
        if let v = value as? LosslessStringConvertible {
            result = v.description
            dlog?.trace("transformIn v: \(v.description) : \(Value.self) as LosslessStringConvertible k: \(key) result: \"\(result.descOrNil)\" ")
        } else if let eValue = value as? Codable {
            let encoder = encoder ?? JSONEncoder()
            let desc = try encoder.encode(eValue)
            result = desc.base64EncodedString()
            dlog?.trace("transformIn v: \(desc) : \(Value.self) as Codable k: \(key) result: \"\(result.descOrNil)\" ")
        } else {
            let msg = "\(self) failed transformIn key: \(key). value: \(value) : \(Value.self)"
            dlog?.error("\(msg)")
            throw MNError(code: .misc_failed_inserting, reason: msg)
        }
        return result
    }
    
    private func internal_transformOut<Value:MNSettableValue>(string:String, key:String, decoder:JSONDecoder? = nil) throws -> Value? {
        // public typealias MNSettableValue = Hashable & Codable & Equatable & CustomStringConvertible
        var result : Value? = nil
        var method_4debug = "?"
        if let Val = Value.self as? LosslessStringConvertible.Type {
            result = Val.init(string) as! Value?
            method_4debug = "\(Value.self) as LosslessStringConvertible.init(string)"
        } else { // trating string as Codable always succeeds because MNSettableValue is : Hashable & Codable & Equatable & CustomStringConvertible
            let decoder = decoder ?? JSONDecoder()
            var procc = [
                {
                    if let data = Data(base64Encoded: string, options: .ignoreUnknownCharacters) {
                        result = try decoder.decode(Value.self, from: data)
                        method_4debug = "base64Encoded.decode(\(Value.self))"
                    }
                },
                {
                    if let data = string.data(using: .utf16) {
                        result = try decoder.decode(Value.self, from: data)
                        method_4debug = "utf16.decode(\(Value.self))"
                    }
                }
                // TODO: see if needed: UnkeyedDecodingUtil.decode
                
            ]
            for proc in procc {
                do {
                    try proc()
                } catch let error {
                    dlog?.error("internal_transformOut error in decoding: \(error.description)")
                }
                
                if result != nil {
                    break
                }
            }
        }
        
        if result != nil {
            dlog?.trace("internal_transformOut: \(method_4debug) -> \(result.descOrNil)")
        } else {
            dlog?.log(level:.warning, "internal_transformOut: \(method_4debug) failed!")
        }
        return result
    }
    
    private func internal_transformOut<Value:MNSettableValue>(string:String, key:String, decoder:JSONDecoder? = nil) throws -> Value? where Value : LosslessStringConvertible {
        let result = Value(string)
        dlog?.trace("internal_transformOut: \"\(string)\" : \(Value.self) as LosslessStringConvertible -> \(result.descOrNil)")
        return result
    }
    
    private func transformOut<Value:MNSettableValue>(string:String?, key:String, decoder:JSONDecoder? = nil) throws -> Value? {
        var result : Value? = nil
        if let str = self.cache.value(forKey: key) {
            result = try self.internal_transformOut(string: str, key: key, decoder: decoder)
        } else {
            dlog?.notice("\(self.description) transformOut has no value for the key: \(key) : \(Value.self)")
            result = nil
        }
        
        return result
    }
    
    public func setAllValuesForKeys(dict: [MNSKey : AnyMNSettableValue]) async throws {
        try await self.setValuesForKeys(dict: dict)
    }
    
    public func setValue<V>(_ value: V, forKey key: MNSKey) async throws where V : MNSettableValue {
        dlog?.trace(">>[5]a    setValue(key: \(key) value: \(value))")
        if let v = try self.transformIn(value: value, key: key) {
            cache[key] = v
        } else {
            dlog?.warning("setValue failed transformIn for key: \(key) value:\(value)")
        }
    }
    
    public func setValuesForKeys(dict: [MNSKey : AnyMNSettableValue]) async throws {
        var count = 0
        do {
            for (k, v) in dict {
                if let v = try self.transformIn(value: v, key: k) {
                    try await self.setValue(v, forKey: k)
                } else {
                    dlog?.warning("setValuesForKeys failed transformIn for key: \(k) value:\(v.description)")
                }
                count += 1
            }
        } catch let error {
            dlog?.warning("setValuesForKeys failed: \(error.description) (after \(count)/\(dict.count) values)")
        }
    }
    
    public func keyWasChanged(from fromKey: MNSKey, to toKey: MNSKey, value: AnyMNSettableValue, context: String, caller: Any?) {
        if let calleroBJ = caller as? any AnyObject {
            guard calleroBJ === self else {
                dlog?.warning("keyWasChanged should be called from self (\(self.description))")
                return
            }
        }
        
        dlog?.trace(">>[5]a    keyWasChanged(fromKey: \(fromKey) toKey: \(toKey))")
        if cache.replaceKey(from: fromKey, to: toKey), let val = cache.value(forKey: toKey) {
            if MNUtils.debug.IS_DEBUG {
                // Validate value?
                if val == value.description {
                    // ?
                } else {
                    dlog?.warning("keyWasChanged replaced key but the value was different for fromKey: \(fromKey.description) toKey: \(toKey.description) value:\(value.description)")
                }
            }
        } else {
            dlog?.warning("keyWasChanged failed transformIn for fromKey: \(fromKey.description) toKey: \(toKey.description) value:\(value.description)")
        }
    }
    
    public func valueWasChanged(key: MNSKey, from fromValue: AnyMNSettableValue, to toValue: AnyMNSettableValue, context: String, caller: Any?) {
        dlog?.trace(">>[5]a    valueWasChanged(key: \(key) fromValue: \(fromValue.description) toValue: \(toValue.description)")
        do {
            if let existingValue = try self.transformIn(value: fromValue, key: key), existingValue == cache.value(forKey: key) {
                Task {
                    try await self.setValue(toValue, forKey: key)
                }
            } else if let newValue = try self.transformIn(value: toValue, key: key), cache.value(forKey: key) != newValue {
                dlog?.warning("valueWasChanged key:\(key) had NEITHER fromValue:\(fromValue.description) nor toValue:\(toValue.description)")
                Task {
                    try await self.setValue(toValue, forKey: key)
                }
            }
        } catch let error {
            dlog?.notice("valueWasChanged key:\(key) fromValue: \(fromValue.description) toValue: \(toValue.description) failed transformIn with error: \(error)")
        }
        
    }
    
    public func getValue<V>(forKey key: MNSKey) throws -> V? where V : MNSettableValue {
        if let str = cache.value(forKey: key) {
            if let result : V = try self.transformOut(string: str, key: key) {
                dlog?.trace("cache[\(self.cache.name)] getValue(forKey: \(key)) == \(result)")
                return result
            } else {
                dlog?.notice("cache[\(self.cache.name)] getValue(forKey: \(key)) returned \"\(str)\" and failed to deceode. keys:\(self.cache.keys.descriptionsJoined)")
            }
        }
        return nil
    }
    
    // MNSettingsProvider
    public func fetchValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V? {
        return try getValue(forKey: key)
    }
    
    public func fetchValues<V>(forKeys keys: [MNSKey]) async throws -> [MNSKey : V]? where V : CustomStringConvertible, V : Decodable, V : Encodable, V : Hashable {
        let keyStrVals = cache.values(forKeys: keys)
        if MNUtils.debug.IS_DEBUG {
            let missingKeys = keys.removing(objects: keyStrVals.keysArray)
            if missingKeys.count > 0 {
                dlog?.notice("fetchValues missing keys: \(missingKeys.descriptionsJoined)")
            }
        }
        var lastKey : MNSKey = ""
        var result : [MNSKey:V] = [:]
        do {
            for (key, strValue) in keyStrVals {
                lastKey = key
                if let value : V = try self.transformOut(string: strValue, key: key) {
                    result[key] = value
                }
            }
        } catch let error {
            dlog?.warning("fetchValues on key:\(lastKey) failed transformOut with error: \(error)")
        }
        
        
        return result
    }
}

extension MNLocalJSONPersistor : MNSettingSaveLoadable {
    public var url: URL? {
        return cache.filePath(forKeysOnlyCache: false)
    }
    
    public func load(info: StringAnyDictionary?) async throws -> Int {

        if let err = await cache.whenLoadedAsync() {
            dlog?.notice("err: \(self.cache.name) failed to load: \(err.description)")
            throw MNError(code: .misc_failed_loading, reason:"MNLocalJSONPersistor failed loading for an unknown reason", underlyingError: err)
        } else {
            // No error on load
            return cache.count
        }
        
        // return .failure(code: .misc_failed_saving, reason:"MNLocalJSONPersistor failed loading for an unknown reason")
    }

    public func save(info: StringAnyDictionary?) async throws -> Int {
        if self.cache.save() {
            return cache.count
        } else {
            throw MNError(code: .misc_failed_saving, reason:"MNLocalJSONPersistor failed loading for an unknown reason")
        }
    }
}

extension MNLocalJSONPersistor : MNCacheObserver {
    
    public func cacheWasSaved(uniqueCacheName: String, keysCount: Int, error: MNCacheError?) {
        dlog?.successOrFail(condition: error == nil,
                            succStr: "MNLocalJSONPersistor [\(self.cache.name)] was saved!",
                            failStr: "MNLocalJSONPersistor [\(self.cache.name)] failed saving with error:\(error.descOrNil)")
    }
    
    public func cacheWasLoaded(uniqueCacheName: String, keysCount: Int, error: MNCacheError?) {
        dlog?.successOrFail(condition: error == nil,
                            succStr: "MNLocalJSONPersistor [\(self.cache.name)] was loaded!",
                            failStr: "MNLocalJSONPersistor [\(self.cache.name)] failed loading with error:\(error.descOrNil)")
    }
}
