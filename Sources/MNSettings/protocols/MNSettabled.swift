//
//  MNSettabled.swift
//  
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation
import MNUtils

typealias AnyMNSettabled = any MNSettabled

protocol MNSettabled : Equatable {
    associatedtype ValType = MNSettableValue
    
    static var associatedType : ValType.Type { get }
    var key : MNSKey { get }
    var uuid : UUID { get } // used to differentiate between two observers of the same key
    /* weak */ var settings : MNSettings? { get }
    
    func setValue(_ newValue:AnyMNSettableValue) throws
    func setDefaultValue(_ newDefaultValue:AnyMNSettableValue) throws
    func getValue(forKey:MNSKey) throws -> ValType
    func setKey(_ newValue:String, context:String) throws
    func fillLoadedValueFromPersistors() async throws // for after loading
    
    // NOTE: we use a setter function with an exotic name instead of a var, so that this operation will be well thought of - it has important consequences
    func setMNSettings(_ newValue:MNSettings, context:String)
}

extension MNSettabled {
    static var associatedType : ValType.Type { return ValType.self }
    
    // MARK: Equatable
    public static func ==(lhs:AnyMNSettabled, rhs:AnyMNSettabled)->Bool {
        return (lhs.key == rhs.key) && MemoryAddress(of:lhs as AnyObject) == MemoryAddress(of:rhs as AnyObject)
    }
}

extension Sequence where Element == AnyMNSettabled {
    var keys : [MNSKey] {
        return self.map { $0.key }
    }
}

