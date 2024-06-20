//
//  MNSettingsProvider.swift
//  
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation
import MNUtils
import Logging

fileprivate let dlog : Logger? = Logger(label: "MNSettingsProvider") // .setting(verbose: true)


/// Implementors should be able to perform fetch operations for key/value pairs from a source
public protocol MNSettingsProvider {
    
    
    /// Fetch a single Value for a given key from the implementor
    /// - Parameter key: key to use to fetch the value
    /// - Returns: the requested value. If the key/value pair do not exist - returns nil, or throws an error if the fetching process failed
    func fetchValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V?
    
    
    /// Fetch multiple values for multiple keys
    /// - Parameter keys: keys for all the reqeusted values
    /// - Returns: array of all *found* values, or throws error. NOTE: not all keys may return a value, hence keys.count may be bigger than result.count.
    func fetchValues<V:MNSettableValue>(forKeys keys:[MNSKey]) async throws -> [MNSKey:V]?
    
    
    /// Fetch all stored key / values in the persistance implementor
    /// - Returns: dictionary of all saved key / value pairs in the implementor or throws an error if the fetch failed
    func fetchAllKeyValues() async throws -> [MNSKey:AnyMNSettableValue]
    
}

public extension MNSettingsProvider {
    
    func fetchAllKeyValues() async throws -> [MNSKey:AnyMNSettableValue] {
        dlog?.todo("Implement fetchAllKeyValues() for \(Self.self)!")
        return [:]
    }
    
    // Delta
    func fetchValues<V:MNSettableValue>(forKeys keys:[MNSKey]) async throws -> [MNSKey:V] {
        dlog?.todo("Implement fetchValues(forKeys:) for \(Self.self)!")
        return [:]
    }
    
    func fetchValue<V:MNSettableValue>(forKey key:MNSKey) async throws -> V? {
        dlog?.todo("Implement fetchValue(forKey:) for \(Self.self)!")
        return nil
    }
}
