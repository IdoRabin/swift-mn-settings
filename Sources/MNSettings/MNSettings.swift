//
//  MNSettings.swift
//
//  Created by Ido Rabin on 24/07/2023.
//  Copyright © 2023 IdoRabin. All rights reserved.
//

import Foundation
import DSLogger
import MNUtils

#if VAPOR
import Vapor
#endif

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettings")

public typealias MNSettableValue = Hashable & Codable & Equatable & Sendable

public protocol MNSettingsProvider {
    // Optional or convenience
    func getValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V?
    func value<V:MNSettableValue>(forKey key:MNSKey) async throws -> V?
    func getAllKeyValues() async throws -> [MNSKey:any MNSettableValue]
}

extension MNSettingsProvider {
    public func getValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V? {
        return try await value(forKey: key)
    }
    
    public func getAllKeyValues() async throws -> [MNSKey:any MNSettableValue] {
        dlog?.todo("Implement getAllKeyValues for \(Self.self)!")
        return [:]
    }
}

public protocol MNSettingsPersistor : MNSettingsProvider {
    // Values
    func setValue<V:MNSettableValue>(_ value:V?, forKey key:MNSKey) async throws
    func setValuesForKeys(dict:[MNSKey:any MNSettableValue]) async throws
    
    // Optional or convenience
    func getValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V?
}

fileprivate var mnSettings_registry : [String:MNSettings] = [:]

public class MNSettings {
    
    // MARK: Const
    static public let DEFAULT_PERSISTORS = [MNUserDefaultsPersistor.standard]
    static public let DEFAULT_MNSETTINGS_NAME = "__default__"
    static public let OTHER_CATERGORY_NAME = "other"
    static public let CATEGORY_DELIMITER = "."
    
    // MARK: Static
    
    // MARK: Properties / members
    private var observers : [MNSKey:any MNSettabled] = [:]
    private (set) var values : [MNSCategoryName:[MNSKey : any MNSettableValue]] = [:]
    private (set) var name: String
    @SkipEncode private (set) var bulkChangeKey : String? = nil
    @SkipEncode private (set) var changes: [String:String]
    @SkipEncode private var lock : MNLock
    
    @SkipEncode private (set) var persistors : [MNSettingsPersistor] = []
    @SkipEncode private (set) var defaultsProvider : MNSettingsProvider? = nil
    
    // MARK: Singleton-ish
    @SkipEncode static private (set) var _standard : MNSettings? = nil
    static var standard : MNSettings {
        get {
            if _standard == nil {
                do {
                    _standard = try MNSettings(named: Self.DEFAULT_MNSETTINGS_NAME, persistors: [MNUserDefaultsPersistor.standard])
                } catch let error {
                    dlog?.raisePreconditionFailure("standard MNSettings was not created: error: \(error.description)")
                }
            }
            
            return _standard!
        }
    }
    
    // MARK: Lifecycle
    public init(named name:String, persistors: [MNSettingsPersistor] = DEFAULT_PERSISTORS, defaultsProvider:MNSettingsProvider? = nil) throws {
        guard name.count > 0 else {
            throw MNError(code:.misc_bad_input, reason: "MNSettings.init(...) name should be at least one charachter")
        }
        
        let instanceNames = mnSettings_registry.keysArray
        guard !instanceNames.contains(elementEqualTo: name) else {
            throw MNError(code:.misc_bad_input, reason: "MNSettings.init(...) named \(name) is already in use!")
        }
        guard persistors.count > 0 else {
            throw MNError(code:.misc_bad_input, reason: "MNSettings.init(...) requires at least one per!")
        }
        
        self.lock = MNLock(name: "\(Self.self).\(name)")
        self.name = name
        self.values = [:]
        self.changes = [:]
        self.persistors = persistors
        self.defaultsProvider = defaultsProvider
        mnSettings_registry[name] = self
    }
    
    // MARK: Private
    fileprivate var categories : [String] {
        get {
            if self.isBulkChangingNow {
                return self.values.keysArray.compactMap { key in
                    let cat = MNSettings.category(forKey: key)
                    if MNUtils.debug.IS_DEBUG && cat == nil {
                        let msg = "DEBUG: var categories[] failed for key: \(key) - key does not contain a category!"
                        dlog?.warning(msg)
                    }
                    return cat
                }
            } else {
                return self.lock.withLock {
                    return self.values.keysArray.compactMap { key in
                        let cat = MNSettings.category(forKey: key)
                        if MNUtils.debug.IS_DEBUG && cat == nil {
                            let msg = "DEBUG: var categories[] failed for key: \(key) - key does not contain a category!"
                            dlog?.warning(msg)
                        }
                        return cat
                    }
                }
            }
        }
    }
    
    var wasChanged : Bool {
        return self.lock.withLock {
            return self.changes.count > 0
        }
    }
    
    fileprivate var isBulkChangingNow : Bool {
        return self._bulkChangeKey.wrappedValue != nil
    }
    
    fileprivate func sanitizeKey (_ key:MNSKey)->MNSKey {
        var key = key.camelCaseToSnakeCase()
        var category = category(forKey:key)
        if category == nil {
            category = Self.OTHER_CATERGORY_NAME
            key = category! + Self.CATEGORY_DELIMITER + key
        }
        
        self.lock.withLock {
            if self.values[category!] == nil {
                self.values[category!] = [:]
            }
        }
        return key
    }
    
    fileprivate func sanitizeDict(_ dict:[MNSKey:any MNSettableValue]) throws -> [MNSKey: any MNSettableValue]  {
        var result :  [MNSKey: any MNSettableValue] = [:]
        
        for (key, val) in dict {
            if MNUtils.debug.IS_DEBUG && self.category(forKey: key) == nil {
                let msg = "DEBUG: sanitizeDict with key: \(key) - key does not contain a category or other fault!"
                // dlog?.note(msg)
                throw MNError(code: .misc_failed_saving, reason: msg)
            }
            
            let skey = self.sanitizeKey(key)
            result[skey] = val
            
        }
        
        return result
    }
    
    public static func category(forKey key : MNSKey, delimiter:String = "")->MNSCategoryName? {
        return key.components(separatedBy: delimiter).first
    }
    
    // MARK: Internal
    func category(forKey key : MNSKey, delimiter:String = "")->MNSCategoryName? {
        return Self.category(forKey: key, delimiter: delimiter)
    }
    
    func registerObserver(_ observer: any MNSettabled) {
        self.observers[observer.key] = observer
    }
    
    // MARK: Public
    public static func instance(byName name:String)->MNSettings? {
        return mnSettings_registry[name]
    }
}

extension MNSettings : MNSettingsPersistor {
    
    fileprivate func unsafeSetValuesIntoPersistors(dict:[MNSKey:any MNSettableValue]) async throws {
        for persistor in self.persistors {
            try await persistor.setValuesForKeys(dict: dict)
        }
    }
        
    fileprivate func unsafeSetValuesForKeys(dict:[MNSKey:any MNSettableValue]) async throws {
        for (key, val) in dict {
            if let category = self.category(forKey: key) {
                var xVals = self.values[category] ?? [:]
                xVals[key] = val
                self.values[category] = xVals
            } else {
                throw MNError(code: .misc_failed_saving, reason: "unsafeSetValuesForKeys key: \(key) - key does not contain a category. (use \(Self.CATEGORY_DELIMITER) as delimiter)")
            }
        }
    }

    fileprivate func unsafeNotifyObservers(changes:[MNSKey: any MNSettableValue], isDefaults:Bool = false) throws {
        for (key, value) in changes {
            if let observer = self.observers[key] {
                if MNUtils.debug.IS_DEBUG && observer.key != key {
                    dlog?.note("unsafeNotifyObservers change for key: \(key) called observer that has another key: \(observer.key)")
                } else {
                    if isDefaults {
                        try observer.setDefaultValue(value)
                    }
                    try observer.setValue(value)
                }
            }
        }
    }
    
    // MNSettable
    public func setValuesForKeys(dict: [MNSKey : any MNSettableValue]) async throws {
        let sdict = try sanitizeDict(dict)
        func exec(settings:MNSettings) async throws {
            try await settings.unsafeSetValuesForKeys(dict: sdict)
            try await settings.unsafeSetValuesIntoPersistors(dict: sdict)
            try self.unsafeNotifyObservers(changes: sdict)
            
        }
        
        if self.isBulkChangingNow {
            try await exec(settings: self)
        } else {
            try await self.bulkChanges(block: { settings in
                try await exec(settings: settings)
            })
        }
    }
    
    public func setValue<V : MNSettableValue>(_ value: V?, forKey key: MNSKey) async throws {
        try await self.setValuesForKeys(dict: [key:value])
    }
    
    public func value<V : MNSettableValue>(forKey key: MNSKey) async throws -> V? {
        let skey = self.sanitizeKey(key)
        guard let category = self.category(forKey: skey) else {
            throw MNError(code: .misc_failed_saving, reason: "value forKey: \(skey) - key does not contain a category. (use \(Self.CATEGORY_DELIMITER) as delimiter)")
        }
        
        let result : V?
        if self.isBulkChangingNow {
            result = self.values[category]?[skey] as? V
        } else {
            result = self.lock.withLock {
                return self.values[category]?[skey] as? V
            }
        }
        
        dlog?.info("value for key: \(skey) value:\(result.descOrNil)")
        
        return result
    }

    // MNSettingsPersistor
    public func bulkChanges(block: @escaping  (_ settings : MNSettings) async throws -> Void) async throws {
        
        var newKey = "\(Self.self).\(self.name)"
        if self.isBulkChangingNow {
            dlog?.warning("\(newKey) bulkChanges - already changing, will wait.")
        }
        
        newKey += Date.now.ISO8601Format()
        self.lock.withLockVoid {
            dlog?.verbose("bulkChanges: \(newKey)")
            self.bulkChangeKey = newKey
            Task {
                // will allow all changes in one lock / unlock bulk and prevent saving while bulk work is in progress
                try await block(self)
            }
            
            self.bulkChangeKey = nil
        }
    }
    
    public func resetToDefaults() async throws {
        try await self.bulkChanges(block: { settings in
            settings.values = [:]
            settings.changes = [:]
            
            // Get all key-values
            if let defaults = try await self.defaultsProvider?.getAllKeyValues() {
                for persistor in self.persistors {
                    try await persistor.setValuesForKeys(dict: defaults)
                }
                try self.unsafeNotifyObservers(changes: defaults, isDefaults: true)
            } else {
                dlog?.note("resetToDefaults - defaultsProvider: \(self.defaultsProvider.descOrNil) failed fetching defaults!")
            }
        })
    }
}

public protocol MNSettingsCategory {
    var categoryName : MNSCategoryName { get }
}

public extension MNSettingsCategory /* default implementation */ {
    var categoryName : MNSCategoryName {
        return "\(Self.self)"
    }
}
