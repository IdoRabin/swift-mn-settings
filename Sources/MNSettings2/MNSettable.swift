//
//  MNSettable.swift
//
//
//  Created by Ido on 30/10/2023.
//

import Foundation

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettable")?.setting(verbose: true)

public typealias MNSettableValue = Codable & Hashable & Equatable
public typealias AnyMNSettableValue = any MNSettableValue

enum MNSettableChangeType : Int, Codable, CaseIterable {
    case client = 1
    case server
    case loaded
}

struct MNSettableChange <Value:MNSettableValue> {
    let ref:MNSettable<Value>
    let fromValue:Value?
    let toValue:Value
    let changeType:MNSettableChangeType
    let caller : Any
}

protocol MNSettableEvent {
    func didChange<Value : MNSettableValue>(change:MNSettableChange<Value>)
}
protocol MNSettableValueContainer {
    associatedtype Value : MNSettableValue
    var valueType : Value.Type { get }
}

@propertyWrapper
class MNSettable<Value : MNSettableValue & Codable> : MNSettingsElement, MNSettableValueContainer, CustomStringConvertible {
    private var _defaultValue : Value? = nil
    private var _value : Value? = nil
    var value : Value {
        get {
            return self._value!
        }
        set {
            if newValue != self._value {
                let prev = self._value
                self._value = newValue
                observers.enumerateOnCurrentThread { observer in
                    observer.didChange(change: MNSettableChange<Value>(ref: self,
                                                                       fromValue: prev,
                                                                       toValue: newValue,
                                                                       changeType: .client,
                                                                       caller: self))
                }
            }
        }
    }
    
    var defaultValue : Value {
        get {
            return self._defaultValue!
        }
        set {
            if newValue != self._defaultValue {
                self.defaultValue = newValue
            }
        }
    }
    
    var valueType : Value.Type {
        return Value.self
    }
    
    var observers = ObserversArray<MNSettableEvent>()
    
    enum CodingKeys : String, CodingKey, CaseIterable {
        case value = "value"
        case defaultValue = "default_value"
    }
    
    // MARK: @propertyWrapper
    var wrappedValue : Value {
        get {
            return _value!
        }
    }
    
    // MARK: Lifecycle
    internal init(_ newValue: Value, defaultValue newDefaultValue: Value, key:MNSKey? = nil, parentKeys : [MNSKey]? = nil) throws {
        let key = key ?? "\(Self.self)|\(Value.self)"
        self._defaultValue = newDefaultValue
        self._value = newValue
        try super.init(key: key, parentKeys: parentKeys)
    }
    
    // MARK: Codable
    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(_value, forKey: CodingKeys.value)
        try container.encodeIfPresent(_defaultValue, forKey: CodingKeys.defaultValue)
    }
    
    public required init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        _value = try keyed.decodeIfPresent(Value.self, forKey: CodingKeys.value)
        _defaultValue = try keyed.decodeIfPresent(Value.self, forKey: CodingKeys.defaultValue)
        try super.init(from: decoder)
    }
    
    // MARK: CustomStringConvertible
    var description: String {
        var valStr = "<nil>"
        var defaultValStr = "<nil>"
        if let val = _value {
            valStr = "\(val)".substring(upTo: 22, whitespaceTolerance: 12)
        }
        if let defaultVal = _defaultValue {
            defaultValStr = "\(defaultVal)".substring(upTo: 22, whitespaceTolerance: 12)
        }
        
        return "<\(Self.self) key:\"\(self.key)\" val:\(valStr) default:\(defaultValStr)>"
    }
}
