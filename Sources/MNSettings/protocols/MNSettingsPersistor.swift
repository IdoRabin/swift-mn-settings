//
//  MNSettingsPersistor.swift
//  
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation
import MNUtils
import Logging

fileprivate let dlog : Logger? = Logger(label: "MNSettingsPersistor") //  DLog.forClass("MNSettingsPersistor")?.setting(verbose: true)


/// Alllows saving / loading operations for a MNSettings provider / implementor
public protocol MNSettingSaveLoadable {
    // Load / save
    var url : URL? { get }
    
    /// Load all the Key / Values using the persistance implementation
    /// - Parameter info: context, settings or instructions to the implementor on how to load
    /// - Returns: number of key / values loaded, or throws an error
    func load(info:StringAnyDictionary?) async throws -> Int
    
    
    /// Save all Key / Values using the persistance implementation
    /// - Parameter info: context, settings or instructions to the implementor on how to save
    /// - Returns: number of keys saved, or throws an error
    func save(info:StringAnyDictionary?) async throws -> Int
}

/// Implementors should be able to perform fetch / put operations for key/value pairs into / from a source
public protocol MNSettingsPersistor : MNSettingsProvider {
    
    
    /// Returns the type name of this persistor, i.e "\(type(of:self))"
    var typeName : String { get }
    
    /// Set a single value for a given key into the persistance implementor, overwriting an existing (if exists) previous value for that key.
    /// - Parameters:
    ///   - value: value to save
    ///   - key: key of the value (as in a key/value dictionary)
    func setValue<V:MNSettableValue>(_ value:V, forKey key:MNSKey) async throws
    
    /// Sets multiple key/values for given keys into the persistance implementor, overwriting existing (if exists) previous values for those keys.
    /// - Parameters:
    ///   - value: value to save
    ///   - dict: key / value pairs to put into the source
    func setValuesForKeys(dict:[MNSKey:AnyMNSettableValue]) async throws
    
    /// Sets all key/values into the persistance implementor, replacing all previous key/values saved
    /// - Parameters:
    ///   - value: value to save
    ///   - dict: key / value pairs to put into the source
    func setAllValuesForKeys(dict:[MNSKey:AnyMNSettableValue]) async throws
    
    // Notifications
    
    /// Notification that a key has changed its name from one key to another, requiring the implementor to replace the old key string with a new string, while keeping the value saved in the source.
    /// - Parameters:
    ///   - fromKey: previous key
    ///   - toKey: new key
    ///   - value: the value to save in the source, can be compared with the existing value in the source to check for discreperancies. as a rule of thumb, the value parameter should take precedence over a value saved in the source that is different.
    ///   - context: string describing the context of hte operation (for debugging mostly)
    ///   - caller: the calling class / body / person / authority info.
    func keyWasChanged(from fromKey: MNSKey, to toKey: MNSKey, value:AnyMNSettableValue, context:String, caller:Any?)
    
    /// Notification that a value for a given key has changed its value, requiring the implementor to replace the old value with the new value
    /// - Parameters:
    ///   - key: key of the value being changed
    ///   - fromValue: previous value
    ///   - toValue: the value to set into the source
    ///   - context: string describing the context of the operation (for debugging mostly)
    ///   - caller: the calling class / body / person / authority info.
    func valueWasChanged(key: MNSKey, from fromValue: AnyMNSettableValue, to toValue:AnyMNSettableValue, context:String, caller:Any?)
}

public extension MNSettingsPersistor {
    /// Returns the type name of this persistor, i.e "\(Self.self)"
    var typeName : String {
        return "\(Self.self)"
    }
}

public extension Array where Element == MNSettingsPersistor {
    var typeNames : [String] {
        return self.map { elem in
            elem.typeName
        }.sorted().uniqueElements()
    }
}
