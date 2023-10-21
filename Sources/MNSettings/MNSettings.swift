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

fileprivate let dlog : DSLogger? = DLog.forClass("MNSettings")?.setting(verbose: false)

public typealias MNSettableValue = Hashable & Codable & Equatable & CustomStringConvertible
public typealias AnyMNSettableValue = any MNSettableValue

// & Sendable TODO: Check how to override "Sendable cannot be used in a conditional cast


// IMPORTANT: registry:
fileprivate var mnSettings_registry : [String:MNSettings] = [:]

public class MNSettings {
    // MARK: Const
    public typealias SettingsLoadedBlock = (_ settings : MNSettings)->Bool /* return true to get unregistered from further whenLoaded's*/
    internal class OtherCategory : MNSettingsCategory { } // Speialized class for other category
    
    // MARK: Types
    enum MNSettingKeysNamingConvetion {
        case camelCase
        case snakeCase
        case unchanged
    }
    
    enum MNSChange : Int, Codable {
        case value
        case key
        
        var asString : String {
            var result = "unknown"
            switch self {
            case .key:   result = "__key_change"
            case .value: result = "value_change"
            }
            
            return "|" + result.uppercased() + "|"
        }
    }
    
    struct MNSChangeRecord {
        let key : MNSKey
        let action : MNSChange
        let from : String?
        let to : String?
    }
    
    // MARK: Consts
    static public let DEFAULT_PERSISTORS = [MNUserDefaultsPersistor.standard]
    static public let DEFAULT_MNSETTINGS_NAME = "__default__"
    static public let OTHER_CATERGORY_NAME = "_other_"
    static public var OTHER_CATERGORY_CLASS_NAME : String {
        return "\(OtherCategory.self)"
    }
    static internal let BOOT_CONTEXT_SUBSTR = "__boot__"
    static public let CATEGORY_DELIMITER = "."
    
    // MARK: Static
    @SkipEncode static public var whenLoaded : [SettingsLoadedBlock] = [] //  wasloaded
    @SkipEncode static var keysNamingConvention : MNSettingKeysNamingConvetion = .snakeCase
    
    // MARK: Properties / members
    // MARK: Private
    // MARK: Lifecycle
    // MARK: Public
    // var children : [Weak<MNSettingsContainer>]
    // weak var parent : MNSettingsContainer
    
    
    // MARK: Static
    
    
    // MARK: Properties / members
    private (set) var values : [MNSCategoryName:[MNSKey : AnyMNSettableValue]] = [:]
    private (set) var name: String
    private (set) var allKeys = Set<String>()
    
    @SkipEncode private var observers : [MNSKey:[AnyMNSettabled]] = [:]
    @SkipEncode private (set) var bulkChangeKey : String? = nil
    @SkipEncode private (set) var changes: [MNSChangeRecord]
    @SkipEncode private var lock : MNLock
    @SkipEncode private (set) var persistors : [any MNSettingsPersistor] = []
    @SkipEncode private (set) var defaultsProvider : (any MNSettingsProvider)? = nil
    @SkipEncode private (set) var providersLoadedCount : Int = 0
    @SkipEncode private (set) var bootState : MNBootState = .unbooted
    
    // MARK: Singleton-ish
    @SkipEncode static private (set) var _standard : MNSettings? = nil
    static var standard : MNSettings {
        get {
            if _standard == nil {
                do {
                    _standard = try MNSettings(named: Self.DEFAULT_MNSETTINGS_NAME, persistors: [MNUserDefaultsPersistor.standard])
                } catch let error {
                    dlog?.raisePreconditionFailure("MNSettings.{standard} MNSettings was not created: error: \(error.description)")
                }
            }
            
            return _standard!
        }
    }
    
    // MARK: Lifecycle
    public init(named name:String, persistors: [any MNSettingsPersistor] = DEFAULT_PERSISTORS, defaultsProvider:(any MNSettingsProvider)? = nil) throws {
        guard name.count > 0 else {
            throw MNError(code:.misc_bad_input, reason: "MNSettings.init(...) name should be at least one charachter")
        }
        
        let instanceNames = mnSettings_registry.keysArray
        guard !instanceNames.contains(elementEqualTo: name) else {
            throw MNError(code:.misc_bad_input, reason: "MNSettings.init(...) named {\(name)} is already in use!")
        }
        guard persistors.count > 0 else {
            throw MNError(code:.misc_bad_input, reason: "MNSettings.init(...) requires at least one persistor/s!")
        }
        
        self.bootState = .booting
        self.lock = MNLock(name: "\(Self.self).\(name)")
        self.name = name
        self.values = [:]
        self.changes = []
        self.persistors = persistors
        self.defaultsProvider = defaultsProvider
        mnSettings_registry[name] = self
        
        let loadStartTime = Date.now
        var allProviders : [any MNSettingsProvider] = self.persistors
        if let def = self.defaultsProvider {
            allProviders.append(def)
        }
        let allProvidersCount = allProviders.count
        
        @Sendable func attemptWhenLoaded() {
            let newProviderCount = self.persistors.count + (self.defaultsProvider != nil ? 1 : 0)
            
            if self.providersLoadedCount >= allProvidersCount {
                
                let delta = abs(loadStartTime.timeIntervalSinceNow)
                
                if newProviderCount > allProvidersCount || delta > 0.099 {
                    dlog?.warning("[\(self.name)] Providers added after load started! waiting for other providers")
                    MNExec.exec(afterDelay: 0.05) {
                        attemptWhenLoaded()
                    }
                    return
                }
                
                dlog?.verbose("\(self.description) Last persistor loaded. \(allProvidersCount) / \(newProviderCount)")
                
                if delta > 0.05 {
                    Self.notifyLoaded(self)
                    self.bootState = .running
                } else {
                    MNExec.exec(afterDelay: delta) {[self] in
                        Self.notifyLoaded(self)
                        self.bootState = .running
                    }
                }
            }
        }
        
        self.bootState = .loading;
        allProviders.forEach {[self] pers in
            if let persistor = pers as? MNSettingSaveLoadable {
                Task {[persistor, self] in
                    dlog?.info("Loading persistor: \(persistor)")
                    let count = try await persistor.load(
                        info: ["name":self.name, "class":Self.self])
                    dlog?.verbose(log: .success, "persistor \(persistor) loaded \(count) items.")
                    
                    // if not thrown error - persistor.load is done
                    self.lock.withLockVoid {
                        self.providersLoadedCount += 1
                    }
                    attemptWhenLoaded() // when all persistors loaded
                }
            } else {
                // Not loadable / savable:
                self.lock.withLockVoid {
                    self.providersLoadedCount += 1
                }
                attemptWhenLoaded() // when all persistors loaded
            }
        }
    }
    
    // MARK: Private
    private var categories : [MNSCategoryName:Weak<MNSettingsCategory>] = [:]
    private var otherCategory : OtherCategory?
    
    var wasChanged : Bool {
        return self.lock.withLock {
            return self.changes.count > 0
        }
    }
    
    fileprivate var isBulkChangingNow : Bool {
        return self._bulkChangeKey.wrappedValue != nil
    }
    
    fileprivate static func notifyLoaded(_ settings:MNSettings, depth:Int = 0) {
        let depth = max(0, depth)
        
        var toRemove : [Int] = []
        if depth < 16 && settings.observers.count < settings.allKeys.count {
            dlog?.note("[\(settings.name)] notifyLoaded delayed \(depth)")
            MNExec.exec(afterDelay: 0.05) {[depth, settings] in
                self.notifyLoaded(settings, depth: depth + 1)
            }
            return
        }
        
        whenLoaded.forEachIndex { index, block in
            if block(settings) {
                toRemove.append(index)
            }
        }
        
        toRemove = toRemove.sorted().reversed() // By index, from high to low
        
        for index in toRemove {
            whenLoaded.remove(at: index) // reversed order
        }
    }
    
    public static func sanitizeString (_ str:String)->String {
        switch Self.keysNamingConvention {
        case .camelCase: return str.snakeCaseToCamelCase()
        case .snakeCase: return str.camelCaseToSnakeCase()
        case .unchanged: return str
        }
    }
    
    public static func sanitizeKey (_ key:MNSKey, delimiter:String = MNSettings.CATEGORY_DELIMITER)->MNSKey {
        var skey = self.sanitizeString(key)
        var category = categoryName(forKey:skey)
        if category == nil {
            category = Self.OTHER_CATERGORY_NAME
            let newKey = category! + Self.CATEGORY_DELIMITER + skey
            dlog?.verbose(log: .note, "sanitizeKey: \"\(key)\" had no category! (changing to \"\(newKey)\")")
            skey = newKey
        }
        
        return skey
    }
    
    fileprivate func sanitizeKey (_ key:MNSKey)->MNSKey {
        let skey = Self.sanitizeKey(key)
        // For debugging? let category = category(forKey:skey)
        return skey
    }
    
    fileprivate func sanitizeDict(_ dict:[MNSKey:AnyMNSettableValue]) throws -> [MNSKey: AnyMNSettableValue]  {
        var result :  [MNSKey: AnyMNSettableValue] = [:]
        
        for (key, val) in dict {
            if MNUtils.debug.IS_DEBUG && self.categoryName(forKey: key) == nil {
                let msg = "{\(name)} DEBUG: sanitizeDict with key: [\(key)] - key does not contain a category or other fault!"
                // dlog?.note(msg)
                throw MNError(code: .misc_failed_saving, reason: "MNSettings." + msg)
            }
            
            let skey = self.sanitizeKey(key)
            result[skey] = val
            
        }
        
        return result
    }
    
    public static func isKeyHasCategory(_ key:MNSKey, delimiter:String = "")->Bool {
        let comps = key.components(separatedBy: delimiter)
        return comps.count < 2
    }
    
    public static func categoryName(forKey key : MNSKey, delimiter:String = MNSettings.CATEGORY_DELIMITER)->MNSCategoryName? {
        var comps = key.components(separatedBy: delimiter)
        guard comps.count > 1 else {
            // dlog?.verbose(log: .note, "{\(name)} categoryName(forKey: \"\(key)\") has no category!")
            return nil
        }
        comps.removeLast()
        return comps.joined(separator: Self.CATEGORY_DELIMITER) // the actual category
    }
    
    // MARK: Internal
    func categoryName(forKey key : MNSKey, delimiter:String = MNSettings.CATEGORY_DELIMITER)->MNSCategoryName? {
        return Self.categoryName(forKey: key, delimiter: delimiter)
    }
    
    func unregisterObserver(_ observer: AnyMNSettabled) {
        var obsList = self.observers[observer.key] ?? []
        obsList.removeAll { setbled in
            setbled.key == observer.key && setbled.uuid == observer.uuid
        }
        if obsList.count == 0 {
            self.observers[observer.key] = nil
        } else {
            self.observers[observer.key] = obsList
        }
    }
    
    func registerObserver(_ observer: AnyMNSettabled) {
        var obsList = self.observers[observer.key] ?? []
        if !obsList.contains(where: { setbled in
            setbled.key == observer.key && setbled.uuid == setbled.uuid
        }) {
            obsList.append(observer)
            self.observers[observer.key] = obsList
            if name != Self.DEFAULT_MNSETTINGS_NAME {
                dlog?.verbose(log: .success, "{\(name)} did registerObserver \(observer)")
            }
        }
    }
    
    func registerCategory(_ cat:MNSettingsCategory) {
        let key = cat.categoryName
        if !self.categories.hasKey(key) {
            self.categories[key] = Weak(value: cat)
        }
    }
    
    internal func createOtherCategoryIfNeeded() {
        if self.otherCategory == nil {
            self.otherCategory = OtherCategory(settings: self, customName: Self.OTHER_CATERGORY_NAME)
            self.categories[Self.OTHER_CATERGORY_NAME] = Weak(value: self.otherCategory!)
        }
    }
    
    func registerSettable<T:MNSettableValue>(_ settable : MNSettable<T>) {
        let key = Self.sanitizeKey(settable.key)
        let cat = Self.categoryName(forKey: settable.key) ?? Self.OTHER_CATERGORY_NAME
        if cat == Self.OTHER_CATERGORY_NAME {
            self.createOtherCategoryIfNeeded()
            self.registerCategory(self.otherCategory!)
        }
        dlog?.verbose("[\(self.name)] registerSettable \(key) cat: \(cat) state: \(self.bootState)")
        self.registerValue(settable.wrappedValue, forKey: key)
    }
    
    func unregisterSettable<T:MNSettableValue>(_ settable : MNSettable<T>) {
        let key = Self.sanitizeKey(settable.key)
        self.unregisterValue(forKey: key)
    }
    
    // MARK: Public
    public static func instance(byName name:String)->MNSettings? {
        return mnSettings_registry[name]
    }
    
    public var isEmpty : Bool {
        return self.lock.withLock {[self] in
            guard observers.count == 0 else {
                dlog?.verbose("\(self).isEmpty: observers.count (\(observers.count))")
                return false
            }
            guard values.count == 0 else {
                dlog?.verbose("\(self).isEmpty: values.count (\(values.count))")
                return false
            }
            guard changes.count == 0 else {
                dlog?.verbose("\(self).isEmpty: changes.count (\(changes.count))")
                return false
            }
            guard categories.count == 0 else {
                dlog?.verbose("\(self).isEmpty: categories.count (\(categories.count))")
                return false
            }
            guard defaultsProvider == nil else {
                dlog?.verbose("\(self).isEmpty: defaultsProvider (\(defaultsProvider.descOrNil))")
                return false
            }
            
            if persistors.count > 0 {
                if persistors.count == 1 && !(persistors.first is MNUserDefaultsPersistor) {
                    dlog?.verbose("\(self).isEmpty: persistors (1) is not MNUserDefaultsPersistor")
                    return false
                } else if persistors.count > 1 {
                    dlog?.verbose("\(self).isEmpty: persistors.count (\(persistors.count))")
                    return false
                }
            }
            
            return true
        }
        
    }
    
    public func debugLogAll() {
        var isDebug = MNUtils.debug.IS_DEBUG
        #if DEBUG
        isDebug = true
        #endif
        #if TESTING
        isDebug = true
        #endif
        
        if isDebug, let dlogAll = DLog.util["MNSettings"] {
            let tab = "   "
            let tab2 = tab.repeated(times: 2)
            
            if self.isEmpty {
                dlogAll.info("- instance [\(self.name)] state: .\(self.bootState) is EMPTY!")
            } else {
                dlogAll.info("- instance [\(self.name)] state: .\(self.bootState)")
                if observers.count > 0 {
                    dlogAll.info(tab + "+ observers (\(observers.count)) for [\(self.name)]")
                    
                    for (oberverKey, observers) in observers.tuplesSortedByKeys { // SEE: private var observers : [MNSKey:[AnyMNSettabled]]
                        let descs = observers.keys.descriptions()
                        if descs.contains(elementEqualTo: oberverKey) {
                            dlogAll.info(tab2 + "observer: key: \(oberverKey). ✔ key")
                        } else {
                            dlogAll.info(tab2 + "observer: key: \(oberverKey) observers: \(descs.descriptionsJoined). ✘ key is IRREGULAR: not one observer with the same key")
                        }
                    }
                }
                
                if categories.count > 0 {
                    
                    // Filter:
                    let rootCategories = self.categories.filter { tup in
                        return (tup.value.value?.nestingLevel ?? -1) == 0
                    }
                    
                    dlogAll.info(tab + "+ root categories \(rootCategories.count) roots / \(categories.count) total categories")
                    for (_, weakCategory) in rootCategories {
                        if let category = weakCategory.value {
                            category.logTree(depth: 2)
                        }
                    }
                }
                
                if values.count > 0 {
                    dlogAll.info(tab + "+ values (\(values.count))")
                    for (catName, vals) in values.tuplesSortedByKeys {
                        let cnt = vals.count
                        if cnt > 0 {
                            dlogAll.info(tab2 + "category: [\(catName)] has (\(cnt)) MNSettables")
                            for (k, v) in vals.tuplesSortedByKeys {
                                dlogAll.info(tab2 + tab + "k: \(k) v: \(v)")
                            }
                        }
                    }
                }
                
                if changes.count > 0 {
                    dlogAll.info(tab + "+ changes (\(changes.count))")
                    for change in changes {
                        dlogAll.info(tab2 + tab + "change: \(change.key) action: \(change.action.asString) from: \(change.from.descOrNil) to: \(change.to.descOrNil)")
                    }
                } else {
                    dlogAll.info(tab + "- changes (\(changes.count)) : NONE")
                }
            }
        }
    }
    
    public func clearChanges() {
        dlog?.note("\(self) clearChanges \(changes.count) state: \(self.bootState)")
        self.changes.removeAll(keepingCapacity: true)
    }
    
    public func hasKey(_ key:String) -> Bool {
        return self.lock.withLock {
            let key = self.sanitizeKey(key)
            if let cat = self.categoryName(forKey: key) {
                return self.values[cat]?.hasKey(key) ?? false
            }
            return false
        }
    }
}

extension MNSettings : Equatable {
    // MARK: Equatable
    public static func ==(lhs:MNSettings, rhs:MNSettings)->Bool {
        return lhs.name == rhs.name
    }
}

extension MNSettings : CustomStringConvertible {
    // MARK: CustomStringConvertible
    public var description: String {
        return "<\(Self.self) \(name)>"
    }
}

extension MNSettings {
    // MARK: Private
    fileprivate func unsafeSetValuesIntoPersistors(dict:[MNSKey:AnyMNSettableValue]) throws {
        
        // Trampoline into non-main thread:
        if Thread.current.isMainThread {
            Task.detached {[dict, self] in
                dlog?.note("unsafeSetValuesIntoPersistors called from MainThread! will use a trampoline (the thrown errors are not handled)")
                do {
                    try self.unsafeSetValuesIntoPersistors(dict:dict)
                } catch let error {
                    dlog?.warning("unsafeSetValuesIntoPersistors called from MainThread threw an unhandled error: \(error.description)")
                }
            }
            return
        }
        
        dlog?.verbose(">>[5]     unsafeSetValuesIntoPersistors dict:\(dict)")
        
        // We block this thred/loop until the Task asyncs are done:
        let arr = Array(self.persistors)
        let total = arr.count
        BlockingTask<Int, MNError> {[self, total, arr] in
            var index = 0
            for persistor in arr {
                do {
                    dlog?.verbose(log:.success, ">>[5]    \(self.name) \(index + 1)/\(total) into: \(type(of:persistor))")
                    try await persistor.setValuesForKeys(dict: dict)
                } catch let err {
                    dlog?.warning(">>[5]    \(self.name) \(index + 1)/\(total) unsafeSetValuesIntoPersistors dict:\(dict) error: \(err.description)")
                    throw err
                }
                index += 1
            }
            return index + 1
        }
        
        // ? ThrowingTaskGroup
        // TODO: Check how to block this thread / loop and return the thrown error from each persistor? also in MainThread? MainActor?
        dlog?.verbose(">>[5]    unsafeSetValuesIntoPersistors: (\(self.persistors.count)) -- DONE")
    }
        
    fileprivate func unsafeSetValuesForKeys(dict:[MNSKey:AnyMNSettableValue], isBoot:Bool) throws {
        for (key, val) in dict {
            if let category = self.categoryName(forKey: key) {
                var xVals = self.values[category] ?? [:]
                xVals[key] = val
                if !isBoot { dlog?.verbose(">>[4]    unsafeSetValuesForKeys >> \(val)") }
                
                if xVals.count == 0 {
                    self.values[category] = nil
                    if !isBoot { dlog?.note(">>[4]a   unsafeSetValuesForKeys cleared vals bcus count was 0") }
                } else {
                    self.values[category] = xVals
                    if !isBoot { dlog?.verbose(">>[4]b   unsafeSetValuesForKeys kept vals") }
                }
            } else {
                throw MNError(code: .misc_failed_saving, reason: "unsafeSetValuesForKeys key: \(key) - key does not contain a category. (use \(Self.CATEGORY_DELIMITER) as delimiter)")
            }
        }
    }

    fileprivate func unsafeNotifyObservers(changes:[MNSKey: AnyMNSettableValue], isDefaults:Bool = false, excluding excluded:[AnyMNSettabled]) throws {
        for (key, value) in changes {
            if var obsList = self.observers[key] {
                
                obsList.removeAll { settble in
                    excluded.contains { excl in
                        excl.key == settble.key && excl.uuid == settble.uuid
                    }
                }
                
                for observer in obsList {
                    var isSkip = false
                    
                    dlog?.verbose(">>[5]   unsafeNotifyObservers isDefaults: \(isDefaults) excluding: \(excluded)")
                    
                    // Skip if observer is in the excluded list:
                    let skipped = excluded.filter { setbled in
                        setbled.key == observer.key && setbled.uuid == observer.uuid
                    }
                    if skipped.count > 0 {
                        isSkip = true
                        // This prevents circular notification when the change was evoked in the AnyMNSettabled and called into the settings using "ValueWasChanged(...caller:)" - we exclude the caller from the notify observers call
                        dlog?.note(">>[5]a   {\(name)} unsafeNotifyObservers change for key: \(key) will skip \(skipped.count) excluded items.")
                    }
                    
                    // TODO: Uncomment if needed. re-check if skipping other keys is ok.
                    // Skip if observer is not of the same key:
                    if MNUtils.debug.IS_DEBUG && observer.key != key {
                        dlog?.note("{\(name)} unsafeNotifyObservers change for key: \(key) called observer that has another key: \(observer.key)")
                        isSkip = true
                    }
                    
                    // Exec if not skip
                    if !isSkip {
                        if isDefaults {
                            try observer.setDefaultValue(value)
                        }
                        try observer.setValue(value)
                    }
                }
            }
        }
    }
    
    fileprivate func unsafeMakeRecordChanges(_ changes:[MNSKey: AnyMNSettableValue], isDefaults:Bool = false) ->[MNSChangeRecord] {
        let records : [MNSChangeRecord] = changes.compactMap { key, value in
            let category = self.categoryName(forKey: key) ?? Self.OTHER_CATERGORY_NAME
            let prevValue = self.values[category]?[key]
            return MNSChangeRecord(key: key, action: .value, from: prevValue?.description, to: value.description)
        }
        return records
    }
    
    @Sendable fileprivate func unsafeSetValuesForKeysExec(dict: [MNSKey : AnyMNSettableValue], excluding:[Any], isBoot:Bool) throws {
        // Assuming dit was sanitized
        let changes = isBoot ? [] : self.unsafeMakeRecordChanges(dict)
        if !isBoot {
            dlog?.verbose(">>[3]  unsafeSetValuesForKeysExec dict:\(dict)")
        }
        
        let excluded = excluding.compactMap { $0 as? AnyMNSettabled } // we filter the excluding items using only the AnyMNSettabled (MNSettables))
        
        try self.unsafeSetValuesForKeys(dict: dict, isBoot:isBoot) // local-most - here in .values property
        if !isBoot {
            try self.unsafeNotifyObservers(changes: dict, excluding: excluded)
            try self.unsafeSetValuesIntoPersistors(dict: dict)
            self.changes.append(contentsOf: changes)
        }
    }
    
    @Sendable fileprivate func setValuesForKeysExec(dict: [MNSKey : AnyMNSettableValue], excluding:[Any], blocking:Bool = false, isBoot:Bool = false) throws {
        
        @Sendable func exec() throws {
            if self.isBulkChangingNow {
                try self.unsafeSetValuesForKeysExec(dict: dict, excluding: [], isBoot: isBoot)
            } else {
                try self.bulkChanges(block: {[dict, isBoot] settings in
                    try self.unsafeSetValuesForKeysExec(dict: dict, excluding: [], isBoot: isBoot)
                })
            }
        }
        
        if blocking {
            try exec()
        } else {
            Task {
                try exec()
            }
        }
    }
    
    // MARK: MNSettable / MNSettingsProvider
    public func setValuesForKeys(dict: [MNSKey : AnyMNSettableValue]) throws {
        let sdict = try sanitizeDict(dict)
        dlog?.verbose(">>[!]  setValuesForKeys dict:\(sdict)")
        try setValuesForKeysExec(dict: dict, excluding: [], blocking:false)
    }
    
    public func setValue<V : MNSettableValue>(_ value: V, forKey key: MNSKey) throws {
        try self.setValuesForKeys(dict: [key:value])
    }
     
    public func getValue<V : MNSettableValue>(forKey key: MNSKey) throws -> V? {
        let skey = self.sanitizeKey(key)
        guard let category = self.categoryName(forKey: skey) else {
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
        
        dlog?.verbose("{\(name)} getValue for key: \(skey) value:\(result.descOrNil)")
        
        return result
    }

    public func unregisterValue(forKey key: MNSKey) {
        let cat = Self.categoryName(forKey: key) ?? Self.OTHER_CATERGORY_NAME
        
        if var vals = self.values[cat], vals.hasKey(key) {
            dlog?.note("\(self.name) unregisterSettable \(key) cat: \(cat)")
            vals.removeValue(forKey: key)
            if vals.count == 0 {
                self.values[cat] = nil  // unRegisterValue
            } else {
                self.values[cat] = vals // unRegisterValue
            }
        } else {
            dlog?.verbose(log:.note, "[\(self.name)] failed to find key: \(key) vals: \(self.values) cats: \(self.categories)")
        }
    }
    
    public func registerValue<V : MNSettableValue>(_ value: V, forKey key: MNSKey) {
        do {
            
            if let val: V = try self.getValue(forKey: key), val.hashValue == value.hashValue {
                // Already registered, same value
                return
            }
            
            let dict = [key:value]
            let sdict = try sanitizeDict(dict)
            try setValuesForKeysExec(dict: sdict, excluding: [], blocking:false, isBoot: true)
        } catch let error {
            dlog?.warning("\(self) registerValue failed: \(error.description)")
        }
    }
    
    public func fetchValueFromPersistors<V : MNSettableValue>(forKey key:String) async throws ->V? {
        guard self.hasKey(key) else {
            dlog?.fail("\(self) fetchValueFromPersistors - has no key: \(key)")
            return nil
        }
        
        
        var vals : [V] = []
        for persistor in self.persistors {
            if let val  : V = try await persistor.fetchValue(forKey: key) {
                dlog?.verbose(log:.success, "\(self) fetchValueFromPersistors - [\(persistor)] returned \(val) : \(type(of:val))")
                vals.append(val)
            }
        }
            
        var resultvalue : V? = nil
        switch vals.count {
        case 0:
            resultvalue = nil
        case 1:
            resultvalue = vals.first
        default:
            // V : Hashable & Codable & Equatable & CustomStringConvertible
            resultvalue = vals.majorityValue(whenTwoVals: .first)
        }
        dlog?.verbose("\(self) fetchValueFromPersistors - for: \(key) returned: \(resultvalue.descOrNil)")
        return resultvalue
    }
    
    // MARK: MNSettingsPersistor
    public func bulkChanges(block: @escaping  (_ settings : MNSettings) throws -> Void) throws {
        
        var newKey = "{\(name)}"
        if self.isBulkChangingNow {
            dlog?.warning("\(newKey) bulkChanges - already changing, will wait.")
        }

        newKey += Date.now.ISO8601Format()
        try self.lock.withLockVoid {
            dlog?.verbose("bulkChanges: \(newKey)")
            self.bulkChangeKey = newKey
            
            // will allow all changes in one lock / unlock bulk and prevent saving while bulk work is in progress
            try block(self)

            self.bulkChangeKey = nil
        }
    }
    
    public func resetToDefaults() async throws {
//        try await self.bulkChanges(block: { settings in
//            settings.values = [:]
//            settings.changes = []
//
//            // Get all key-values
//            if let defaults = try await self.defaultsProvider?.getAllKeyValues() {
//                for persistor in self.persistors {
//                    try await persistor.setValuesForKeys(dict: defaults)
//                }
//                try self.unsafeNotifyObservers(changes: defaults, isDefaults: true, excluding: [])
//            } else {
//                dlog?.note("{\(self.name)} resetToDefaults - defaultsProvider: \(self.defaultsProvider.descOrNil) failed fetching defaults!")
//            }
//        })
    }
    
    private func appendChange(key:MNSKey, action:MNSChange, from:String?, to:String?) {
        self.changes.append(MNSChangeRecord(key: key, action: action, from: from, to: to))
        dlog?.verbose("{\(self.name)} MNSChangeRecord for key: \(key) action: \(action.asString) from: \(from.descOrNil) to: \(to.descOrNil)")
    }
    
    public func keyWasChanged(from fromKey: MNSKey,
                              to toKey: MNSKey,
                              value:AnyMNSettableValue,
                              context:String,
                              caller:Any?) {
        guard fromKey != toKey else {
            dlog?.note("keyWasChanged - changed with exactly itself - no action was taken!")
            return
        }
        
        let isBoot = context.contains(MNSettings.BOOT_CONTEXT_SUBSTR)
        
        // Switch in observers:
        observers.replaceKey(fromKey: fromKey, toKey: toKey)
        
        // Switch in values
        if let fromCat = self.categoryName(forKey: fromKey) {
            if var vals = values[fromCat] {
                let prev = vals[fromKey]?.description ?? "<nil>"
                
                vals[fromKey] = nil
                if vals.count == 0 {
                    values[fromCat] = nil
                } else {
                    values[fromCat] = vals
                }
                
                if !isBoot {
                    self.appendChange(key: fromKey, action: .value, from: prev, to: nil)
                    self.appendChange(key: fromKey, action: .key, from: fromKey, to: nil)
                }
            }
        }
        
        if let toCat = self.categoryName(forKey: toKey) {
            var vals = values[toCat] ?? [:]
            vals[toKey] = value // Set new value
            if vals.count == 0 {
                values[toCat] = nil
            } else {
                values[toCat] = vals
            }
            
            if !isBoot {
                self.appendChange(key: toKey, action: .key, from: nil, to: toKey)
                self.appendChange(key: toKey, action: .value, from: nil, to: value.description)
            }
        }
        
        // Notify persistors of change:
        if !isBoot {
            for persistor in persistors {
                persistor.keyWasChanged(from: fromKey, to: toKey, value: value, context: context, caller: caller)
            }
        }
        
        // Defaults provider is read-only and should not get this message.
    }
    
    public func valueWasChanged(key: MNSKey,
                                from fromValue: AnyMNSettableValue,
                                to toValue:AnyMNSettableValue,
                                context:String,
                                caller:Any?) {
        dlog?.verbose(">>[2]  valueWasChanged for: \(key) from:\(fromValue) to:\(toValue)")
        // Validate in values
        if let category = self.categoryName(forKey: key) {
            var vals = values[category] ?? [:]
            var shouldChange = false
            if let existingVal = vals[key] {
                if existingVal.hashValue == fromValue.hashValue {
                    vals[key] = toValue
                    shouldChange = true
                    dlog?.verbose(">>[2]a Will change! \(existingVal) == \(toValue) hashValues are NOT equal (cur saved [\(existingVal)] was the fromValue)!")
                    
                } else if existingVal.hashValue == toValue.hashValue{
                    // dlog?.verbose(log: .fail, "{\(self.name)} valueWasChanged did not need to change - new value was already set!")
                    dlog?.verbose(">>[2]b Will not change: \(existingVal) == \(toValue) (cur saved [\(existingVal)] was already the toValue)")
                } else {
                    vals[key] = toValue
                    shouldChange = true
                    dlog?.verbose(">>[2]c Will change: \(existingVal) != \(toValue) (cur saved [\(existingVal)] was not the from and not the to value)")
                }
            } else {
                dlog?.verbose(log: .success, "{\(self.name)} valueWasChanged did change - new value was never set!")
                vals[key] = toValue
                shouldChange = true
            }
            
            // Set and notify
            if shouldChange {
                // Set back into dict:
                let sdict = [key:toValue]
                var excluded : [Any] = []
                if let caller = caller as? AnyMNSettabled {
                    excluded = [caller]
                }
                do {
                    if self.isBulkChangingNow {
                        try self.unsafeSetValuesForKeysExec(dict: sdict, excluding: excluded, isBoot: false)
                    } else {
                        try self.bulkChanges(block: { settings in
                            try self.unsafeSetValuesForKeysExec(dict: sdict, excluding: excluded, isBoot: false)
                        })
                    }
                } catch let error {
                    dlog?.note("valueWasChanged failed try with error: \(error.description)")
                }
            }
        }
    }
}
