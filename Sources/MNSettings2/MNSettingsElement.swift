//  MNSettingsElement.swift
//
//
//  Created by Ido on 08/08/2023.
//

import Foundation
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettingsElement")?.setting(verbose: false)

public typealias MNSKey = String

extension Array where Element : Weak<MNSettingsElement> {
    var keys : [MNSKey] {
        return self.compactMap{ elem in
            elem.value?.key
        }
    }
}

extension Array where Element : MNSettingsElement {
    var keys : [MNSKey] {
        return self.map { elem in
            elem.key
        }
    }
}

class MNSettingsElement : Codable, Hashable, Equatable {
    // MARK: Types
    // MARK: Const
    // MARK: Static
    static let KEYS_DELIMITER = "."
    
    enum CodingKeys : String, CodingKey, CaseIterable {
        case keyPath = "key_path"
        case key = "key"
        case parentKeys = "parent_keys"
        case childrenKeys = "children_keys"
    }
    
    // MARK: Properties / members
    var key : MNSKey
    var parentKeys : [MNSKey]? = nil
    var childrenKeys : [MNSKey]? = nil
    
    var parent : Weak<MNSettingsElement>? = nil {
        didSet {
            let pkeys = self.allParents.keys
            self.parentKeys = (pkeys.count > 0) ? pkeys : nil
        }
    }
    
    private (set) var children : [Weak<MNSettingsElement>]? = nil {
        didSet {
            self.childrenKeys = children?.keys
        }
    }
    
    var root : MNSettingsElement {
        var elem : Weak<MNSettingsElement>? = self.parent
        while elem?.value?.parent != nil {
            elem = elem?.value?.parent
        }
        return elem?.value ?? self
    }
    
    var allParents : [MNSettingsElement] {
        var result : [MNSettingsElement] = []
        var elem : Weak<MNSettingsElement>? = self.parent
        while elem != nil {
            if let elem = elem, elem.value != nil {
                result.insert(elem.value!, at: 0)
            }
            elem = elem?.value?.parent
        }
        return result
    }
    
    var keysPath : [MNSKey] {
        var result = self.allParents.keys
        if self.parent == nil || result.count == 0 {
            result = (self.parentKeys ?? []).appending(self.key)
        }
        
        result.append(self.key) // last
        return result
    }
    
    var keysPathAsFullKey : MNSKey {
        return self.keysPath.joined(separator: Self.KEYS_DELIMITER) // as! MNSKey
    }
    
    // MARK: Private
    func registerIfNeeded() {
        // ?
    }
    
    // MARK: Public
    func hasChild(_ child:MNSettingsElement) -> Bool {
        guard let children = children else {
            return false
        }
        
        return children.contains(weakValueOf: child)
    }
    
    func addChildren(_ childs : [MNSettingsElement]) {
        let toPut = childs.removing(objects: self.children?.values ?? [])
        guard toPut.count > 0 else {
            return
        }
        
        if children == nil {
            self.children = []
        }
        self.children?.append(contentsOf: toPut.map({ elem in
            elem.parent = Weak(value: self)
            return Weak(value: elem)
        }))
        
        // Remove from waiting list
        MNSettingsMgr.shared.removeFromRegisterWaitlist(childs)
    }
    
    func removeChildren(_ childs : [MNSettingsElement]) {
        guard self.children?.count ?? 0 > 0 else {
            return
        }
        
        let toRemove = childs.intersection(with: self.children!.values)
        guard toRemove.count > 0 else {
            return
        }
        
        self.children?.remove(where: { aweak in
            if let val = aweak.value {
                return toRemove.contains(elementEqualTo: val)
            }
            return false
        })
    }
    
    // MARK: Lifecycle
    // NOTE: Should match @propertywrapper for futher implemetation:
    init(key:MNSKey? = nil, parentKeys:[MNSKey]? = nil) {
        guard type(of: self) != MNSettingsElement.self else {
            let err = MNError(.misc_failed_creating, reason: "MNSettingsElement needs to be subclassed to be used!")
            preconditionFailure(err.desc)
        }
        guard type(of: self) != MNSettingsCategory.self else {
            let err = MNError(.misc_failed_creating, reason: "MNSettingsCategory needs to be subclassed to be used!")
            preconditionFailure(err.desc)
        }
        guard type(of: self) != MNSettings.self else {
            let err = MNError(.misc_failed_creating, reason: "MNSettings needs to be subclassed to be used!")
            preconditionFailure(err.desc)
        }
        
        self.key = key ?? "\(Self.self)"
        self.parentKeys = parentKeys
        dlog?.info("\(Self.self) init(key: \"\(self.key)\" )")
        registerIfNeeded()
    }
    
    // MARK: Equatable
    static func ==(lhs:MNSettingsElement, rhs:MNSettingsElement)->Bool {
        return lhs.keysPath == rhs.keysPath
    }
    
    // MARK: HasHable
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.keysPath)
    }
    
    // MARK: Codable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.key, forKey: CodingKeys.key)
        try container.encodeIfPresent(self.parentKeys, forKey: CodingKeys.parentKeys)
        try container.encodeIfPresent(self.childrenKeys, forKey: CodingKeys.childrenKeys)
    }
    
    required public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try keyed.decode(MNSKey.self, forKey: CodingKeys.key)
        self.parentKeys = try keyed.decodeIfPresent([MNSKey].self, forKey: CodingKeys.parentKeys)
        self.childrenKeys = try keyed.decodeIfPresent([MNSKey].self, forKey: CodingKeys.childrenKeys)
        registerIfNeeded()
        dlog?.info("\(Self.self) init(from decoder:) \"\(self.key)\"")
    }
}
