//
//  MNSettable.swift
//  
//
//  Created by Ido on 08/08/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettable")

public typealias MNSCategoryName = String
public typealias MNSKey = String

// Registry
protocol MNSettabled {
    associatedtype ValType = MNSettableValue
    
    var key : MNSKey { get }
    func setValue(_ newValue:(any MNSettableValue)?) throws
    func setDefaultValue(_ newDefaultValue:(any MNSettableValue)?) throws
    func getValue(forKey:MNSKey) throws -> ValType?
}

final class MNSettable<ValueType : MNSettableValue> : Codable {
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
    private (set) var defaultValue : ValueType?
    private var _value : ValueType?
    private (set) var key : MNSKey
    private weak var settings : MNSettings? = MNSettings.standard
    
    // MARK: Lifecycle
    init(key:MNSKey, value:ValueType?, `default` def:ValueType? = nil, settings:MNSettings? = nil) {
        self.lock.changeName(to: "\(MNSettable.self).\(key)")
        self._value = value
        self.defaultValue = def
        self.key = key
        self.settings = settings ?? MNSettings.standard
    }
    
    // MARK: Codable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode only whats needed
        self.key = try container.decode(MNSKey.self, forKey: .key)
        self._value = try container.decode(ValueType.self, forKey: .value)
        self.lock.changeName(to: "\(MNSettable.self).\(self.key)")
        
        if decoder.userInfo[Self.IGNORE_DEFAULTS_KEY] as? Bool == false {
            self.defaultValue = try container.decodeIfPresent(ValueType.self, forKey: CodingKeys.defaultValue)
        } else {
            self.defaultValue = nil
        }
        
        if let settingsName = try container.decodeIfPresent(String.self, forKey: .settingsName) {
            if let instance = MNSettings.instance(byName: settingsName) {
                self.settings = instance
            } else {
                dlog?.note("init(from decoder:) did not find instance for settingsName: \(settingsName). using .standard")
                self.settings = MNSettings.standard
            }
        }
        
        self.registerToSettings()
    }
    
    func encode(to encoder: Encoder) throws {
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
    
    func category(forKey key : MNSKey, delimiter:String = "")->MNSCategoryName? {
        return MNSettings.category(forKey: key, delimiter: delimiter)
    }
}

extension MNSettable : MNSettabled {
    
    fileprivate func registerToSettings() {
        (settings ?? MNSettings.standard).registerObserver(self)
    }
    
    func getValue(forKey akey:MNSKey) throws ->ValueType? {
        return try self.lock.withLock {
            if self.key != akey {
                throw MNError(code: .misc_failed_loading, reason: "getValue(forKey: \(akey) failed becuase wrong key! \(self.key)")
            }
            
            return self._value
        }
        
    }
    
    func setValue(_ newValue: (any MNSettableValue)? = nil) throws {
        try self.lock.withLockVoid {
            if let newValue = newValue {
                if let val = newValue as? ValueType {
                    self._value = val
                } else {
                    throw MNError(code: .misc_failed_inserting, reason: "Failed setValue with type mismatch! \(Self.self) key: \(self.key) has value type of: \(ValueType.self), not \(type(of:newValue)).")
                }
                
            } else {
                self._value = nil
            }
        }
    }
    
    func setDefaultValue(_ newDefaultValue: (any MNSettableValue)?) throws {
        try self.lock.withLockVoid {
            if let newDefaultValue = newDefaultValue {
                if let val = newDefaultValue as? ValueType {
                    self.defaultValue = val
                } else {
                    throw MNError(code: .misc_failed_inserting, reason: "Failed setDefaultValue with type mismatch! \(Self.self) key: \(self.key) has value type of: \(ValueType.self), not \(type(of:newDefaultValue)).")
                }
                
            } else {
                self.defaultValue = nil
            }
        }
    }
    
}
