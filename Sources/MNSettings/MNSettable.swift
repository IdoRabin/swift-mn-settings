//
//  MNSettable.swift
//  
//
//  Created by Ido on 08/08/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettable_")?.setting(verbose: true)
fileprivate let dlogRegistry : DSLogger? = DLog.forClass("MNSettable_REG")

public typealias MNSCategoryName = String
public typealias MNSKey = String

@propertyWrapper
public final class MNSettable<ValueType : MNSettableValue> : Codable {
    static private var IGNORE_DEFAULTS_KEY : CodingUserInfoKey { CodingUserInfoKey(rawValue: "MNSettable_ignores_defaults")! }
    
    // MARK: Const
    enum CodingKeys : String, CodingKey, CaseIterable {
        case key  = "key"
        case value = "value"
        case defaultValue = "default_value"
        case settingsName = "settings_name"
    }
    
    // MARK: Properties / members
    nonisolated private let lock = MNLock(name: "\(MNSettable.self)")
    private (set) var defaultValue : ValueType
    private var _value : ValueType
    private (set) var key : MNSKey
    private(set) public var projectedValue: MNSettable<ValueType>? = nil // Will allow accessing the MNSettable wrapper itself
    
    // MARK: @propertywrapper
    public var wrappedValue: ValueType {
        get {
            return self._value
        }
        set {
            do {
                try self.setValue(newValue)
            } catch let error {
                dlog?.warning("\(Self.self).\(key) setWrapperdValue failed with error: \(error.description)")
            }
        }
    }
    
    internal (set) public weak var settings : MNSettings? = MNSettings.standard {
        didSet {
            if let old = oldValue, old != settings {
                // Unregister from previous settings instance
                self.unregisterFromSettings(old)
            }
            self.registerToSettings()
        }
    }
    
    let uuid: UUID = UUID()
    
    // MARK: Lifecycle
    public init(wrappedValue wv:ValueType? = nil, key:MNSKey, `default` def:ValueType, settings:MNSettings? = nil) {
        let fsettings = settings ?? MNSettings.standard
        let sanitizedKey = fsettings.sanitizeKey(key)
        self.lock.changeName(to: "\(MNSettable.self).\(sanitizedKey)")
        self._value = wv ?? def
        self.defaultValue = def
        self.settings = fsettings
        self.key = sanitizedKey
        self.projectedValue = self
        self.registerToSettings()
    }
    
    public init(forSettingsNamed settingsName:String, wrappedValue wv:ValueType? = nil, key:MNSKey, `default` def:ValueType) {
        self.lock.changeName(to: "\(MNSettable.self).\(key)")
        self._value = wv ?? def
        self.defaultValue = def
        let fsettings = settings ?? MNSettings.standard
        let sanitizedKey = fsettings.sanitizeKey(key)
        self.settings = fsettings
        self.key = sanitizedKey
        self.projectedValue = self
        if settingsName != self.settings?.name {
            // DO NOT! self.waitForSettingsNamed(settingsName) // using MNExec waitFor...
            // Using completion block observation
            let block : (MNSettings)->Bool = {[self] asettings in
                if settingsName == asettings.name {
                    dlog?.success("[\(asettings.name)] key: \(self.key) recieved settingsName [\(settingsName)] state: [\(asettings.bootState)] was loaded block (delayed)")
                    
                    // fix key if no category:
                    var cat = asettings.categoryName(forKey: self.key, delimiter: MNSettings.CATEGORY_DELIMITER)
                    if cat == nil {
                        self.key = asettings.sanitizeKey(key)
                        cat = asettings.categoryName(forKey: self.key, delimiter: MNSettings.CATEGORY_DELIMITER)
                    }
                    
                    // Move to new settings:
                    self.setMNSettings(asettings, context: "MNSettable.init(forSettingsNamed:)...whenLoaded(...\(settingsName)")
                    asettings.registerSettable(self)
                    asettings.registerObserver(self)
                    return true // should remove from further whenLoaded calls
                }
                return false
            }
            
            // Add to whenLoaded callback blocks..
            MNSettings.whenLoaded.append(block)
        }
    }
    
    // MARK: Codable
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode only whats needed
        self.key = try container.decode(MNSKey.self, forKey: .key)
        self._value = try container.decode(ValueType.self, forKey: .value)
        self.lock.changeName(to: "\(MNSettable.self).\(self.key)")
        
        if (decoder.userInfo[Self.IGNORE_DEFAULTS_KEY] as? Bool) ?? false == false {
            if let val = try container.decodeIfPresent(ValueType.self, forKey: CodingKeys.defaultValue) {
                self.defaultValue = val
            } else {
                let msg = "init(from decoder:) key: \(self.key) try container.decodeIfPresent(ValueType.self, forKey:.defaultValue) returned nil or failed decoding"
                dlog?.note(msg)
                throw MNError(code: .misc_failed_loading, reason: msg)
            }
        } else {
            let msg = "init(from decoder:) decoder.userInfo[Self.IGNORE_DEFAULTS_KEY] - we ignore the loaded defaults"
            dlog?.note(msg)
            throw MNError(code: .misc_failed_loading, reason: msg)
        }
        
        if let settingsName = try container.decodeIfPresent(String.self, forKey: .settingsName) {
            if let instance = MNSettings.instance(byName: settingsName) {
                self.settings = instance
            } else {
                dlog?.note("init(from decoder:) did not find instance for settingsName: \(settingsName). using .standard")
                self.settings = MNSettings.standard
            }
        }
        
        self.projectedValue = self
        self.registerToSettings()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try lock.withLockVoid {
            try container.encode(self.key,   forKey: .key)
            try container.encode(self._value, forKey: .value)
            if encoder.userInfo[Self.IGNORE_DEFAULTS_KEY] as? Bool == false {
                try container.encodeIfPresent(self.defaultValue, forKey: .defaultValue)
            }
            try container.encodeIfPresent(self.settings?.name, forKey: .settingsName)
        }
    }
    
    func resetToDefault() throws {
        lock.withLockVoid {
            self._value = self.defaultValue
        }
    }
    
    func categoryName(forKey key : MNSKey, delimiter:String = MNSettings.CATEGORY_DELIMITER)->MNSCategoryName? {
        return (self.settings ?? MNSettings.standard).categoryName(forKey: key, delimiter: delimiter)
    }
    
    func fetchValueFromPersistors() async throws ->ValueType? {
        return try await settings?.fetchValueFromPersistors(forKey: self.key)
    }
}

extension MNSettable : CustomStringConvertible {
    public var description: String {
        return "<\(Self.self) \"\(key)\">"
    }
}

extension MNSettable : MNSettabled {
    
    // MARK: Equatable
    public static func == (lhs: MNSettable<ValueType>, rhs: MNSettable<ValueType>) -> Bool {
        return (lhs.key == rhs.key) && MemoryAddress(of:lhs) == MemoryAddress(of:rhs)
        //String(memoryAddressOf: lhs as AnyObject) == String(memoryAddressOf: rhs as AnyObject)
    }
    
    fileprivate func unregisterFromSettings(_ oldSettings:MNSettings) {
        oldSettings.unregisterObserver(self)
        oldSettings.unregisterSettable(self)
    }
    
    fileprivate func registerToSettings(_ depth: Int = 0) {
        // NOTE: Timed Recursive
        guard depth < 16 else {
            return
        }
        
        // dlog?.info("\(self.key) will registerObserver in: \((settings?.name).descOrNil)")
        let stt = (settings ?? MNSettings.standard)
        stt.registerObserver(self)
        MNExec.exec(afterDelay: 0.03) {[self, stt] in
            if let curStt = self.settings {
                if stt.name == curStt.name {
                    stt.registerSettable(self)
                } else {
                    stt.unregisterSettable(self)
                    stt.unregisterValue(forKey: self.key)
                    stt.unregisterObserver(self)
                    
                    // Try to register again?
                    curStt.registerSettable(self)
                }
            }
        }
    }
    
    func getValue(forKey akey:MNSKey) throws ->ValueType {
        return try self.lock.withLock {
            if self.key != akey {
                throw MNError(code: .misc_failed_loading, reason: "getValue(forKey: \(akey) failed becuase wrong key! \(self.key)")
            }
            
            return self._value
        }
    }
    
    func setValue(_ newValue:AnyMNSettableValue, forceUpdate:Bool = false) throws {
        guard let newVal = newValue as? ValueType else {
            throw MNError(code: .misc_failed_inserting, reason: "Failed setValue with type mismatch! \(Self.self) key: \(self.key) has value type of: \(ValueType.self), not \(type(of:newValue)).")
        }
        guard forceUpdate || newVal != _value else {
            // No need to set the value again...
            dlog?.verbose(log: .note, "\(Self.self) key: \(self.key) setValue - value \(newVal) is already set!")
            return
        }
        
        let context = "MNSettable.\(self.key).setValue"
        let prev = self._value
        self.lock.withLockVoid {
            self._value = newVal
            dlog?.verbose(">>[1]  MNSettable.\(self.key).setValue from: \(prev) to: \(newVal)")
            
            // Notify within lock
            self.settings?.valueWasChanged(
                key: self.key,
                from: prev,
                to: newVal,
                context: context,
                caller: self)
        }
    }
    
    func setValue(_ newValue: AnyMNSettableValue) throws {
        // we need a seperate func to conform to MNSettabled
        try self.setValue(newValue, forceUpdate: false)
    }
    
    func setDefaultValue(_ newDefaultValue: AnyMNSettableValue) throws {
        try self.lock.withLockVoid {
            if let val = newDefaultValue as? ValueType {
                self.defaultValue = val
            } else {
                throw MNError(code: .misc_failed_inserting, reason: "Failed setDefaultValue with type mismatch! \(Self.self) key: \(self.key) has value type of: \(ValueType.self), not \(type(of:newDefaultValue)).")
            }
        }
    }
    
    func setKey(_ newValue:String, context:String) throws {
        let skey = self.settings?.sanitizeKey(key) ?? MNSettings.staticSanitizeKey(newValue)
        guard skey.count > 0 && MNSettings.isKeyHasCategory(skey) else {
            throw MNError(code: .misc_bad_input, reason: "\(Self.self).setKey failed with new key: \(skey) - it does not contain a category. Use \(MNSettings.CATEGORY_DELIMITER) as a delimiter. first value is the category.")
        }
        if skey != key {
            // dlog?.verbose(log: .success, "Set new key: \"\(key)\" => \"\(skey)\" ")
            let prev = key
            self.key = skey
            
            settings?.keyWasChanged(
                from: prev,
                to: skey,
                value: self._value,
                context: context,
                caller: self)
        }
    }
    
    func setMNSettings(_ newValue: MNSettings, context: String) {
        if let prev = self.settings {
            if newValue == prev {
                return
            }
            self.unregisterFromSettings(prev)
        }
        self.settings = newValue
        self.registerToSettings()
    }
}
