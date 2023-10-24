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

// & Sendable TODO: Check how to override "Sendable cannot be used in a conditional cast"

// IMPORTANT: registry:
fileprivate var mnSettings_registry : [String:Weak<MNSettings>] = [:]
fileprivate var mnSettings_registryLock = MNLock(name: "mnSettings_registry_lock")

protocol MNSettingsRegistrable {
    func findAndRegisterChildCategories()
    func findAndRegisterChildProperties()
}

open class MNSettings {
    public typealias SelfType = MNSettings
    public typealias MNSettingsLoadedBlock = (_ settings : SelfType)->Bool /* return true to get unregistered from further whenLoaded's*/
    public typealias MNSettingsCompletionBlock = (_ settings : SelfType) throws -> Void
    public typealias MNSettingsAsyncCompletionBlock = (_ settings : MNSettings) async throws -> Void
    
    // MARK: Const
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
    static public let DEFAULT_PERSISTORS : [any MNSettingsPersistor] = [MNUserDefaultsPersistor.standard]
    static public let DEFAULT_MNSETTINGS_NAME = "__default__"
    static public let OTHER_CATERGORY_NAME = "_other_"
    static public var OTHER_CATERGORY_CLASS_NAME : String {
        return "\(OtherCategory.self)"
    }
    static internal let BOOT_CONTEXT_SUBSTR = "__boot__"
    static public let CATEGORY_DELIMITER = "."
    
    
    /// Set to false when you are never using the .standard settings and don't want to waste time on loading it upon init. Set this flag as early as possible in the init process of the program.
    /// NOTE: this means that .standart (__default__) settings will always init empty, and will not persist info
    static public var IS_SHOULD_LOAD_DEFAULT_STD_SETTINGS = true
    
    
    /// When true, will check every settings key to use only the registered MNSettingsCategory keys as prefixes or use the __other__ category as prefix. When false, does not check category names (faster) and does not prefix with "other" if not part of MNSettingsCategory and has at least one delimiter in the keys' name.
    /// For example: for the @Settable(key:"myCategory.myKey", default...) will "sanitize" its key:
    /// When true:  to "other.myCategory.myKey" and its category will be: "other.myCategory"
    /// When false: to "myCategory.myKey"        and its category will be: "myCategory"
    static public var IS_SHOULD_USE_ONLY_REG_CATEGORIES = false
    
    static public let DEBUG_IS_SHOULD_DELAY_LOAD : Bool = MNUtils.debug.IS_DEBUG && false // seconds
    static public let DEBUG_LOAD_DELAY : TimeInterval = 2.0 // seconds
    
    // MARK: Static
    @SkipEncode static public var whenLoaded : [MNSettingsLoadedBlock] = [] //  wasloaded
    @SkipEncode static var keysNamingConvention : MNSettingKeysNamingConvetion = .snakeCase
    
    // MARK: Properties / members
    // MARK: Private
    // MARK: Lifecycle
    // MARK: Public
    
    // MARK: Static
    
    
    // MARK: Properties / members
    private (set) var values : [MNSCategoryName:[MNSKey : AnyMNSettableValue]] = [:]
    private (set) public var name: String
    private (set) var allKeys = Set<String>()
    
    @SkipEncode private var observers : [MNSKey:[AnyMNSettabled]] = [:]
    @SkipEncode private (set) var bulkChangeKey : String? = nil
    @SkipEncode private (set) var changes: [MNSChangeRecord]
    @SkipEncode private var lock : MNLock
    @SkipEncode private (set) var persistors : [any MNSettingsPersistor] = []
    @SkipEncode private (set) var defaultsProvider : (any MNSettingsProvider)? = nil
    @SkipEncode private (set) var providersLoadedCount : Int = 0
    @SkipEncode private (set) public var bootState : MNBootState = .unbooted
    
    // MARK: Singleton-ish
    @SkipEncode static private (set) var _standard : MNSettings? = nil
    public static var standard : MNSettings {
        get {
            if _standard == nil {
                _standard = MNSettings(named: Self.DEFAULT_MNSETTINGS_NAME, persistors: [MNUserDefaultsPersistor.standard])
            }
            
            return _standard!
        }
    }
    
    // MARK: Lifecycle
    public required init(named name:String, persistors: [any MNSettingsPersistor] = DEFAULT_PERSISTORS, defaultsProvider:(any MNSettingsProvider)? = nil) {
        guard name.count > 0 else {
            let err = MNError(code:.misc_bad_input, reason: "MNSettings.init(...) name should be at least one charachter")
            preconditionFailure(err.description)
        }
        
        var instanceNames : [String] = []
        mnSettings_registryLock.withLock {
            instanceNames = mnSettings_registry.keysArray
        }

        guard !instanceNames.contains(elementEqualTo: name) else {
            let err = MNError(code:.misc_bad_input, reason: "MNSettings.init(...) named {\(name)} is already in use!")
            preconditionFailure(err.description)
        }
        guard persistors.count > 0 else {
            let err = MNError(code:.misc_bad_input, reason: "MNSettings.init(...) requires at least one persistor/s!")
            preconditionFailure(err.description)
        }
        
        self.bootState = .booting
        self.lock = MNLock(name: "\(Self.self).\(name)")
        self.name = name
        self.values = [:]
        self.changes = []
        self.persistors = persistors
        self.defaultsProvider = defaultsProvider
        
        mnSettings_registryLock.withLock {
            mnSettings_registry[name] = Weak(value: self)
        }
        
        let loadStartTime = Date.now
        var allProviders : [any MNSettingsProvider] = self.persistors
        if let def = self.defaultsProvider {
            allProviders.append(def)
        }
        let allProvidersCount = allProviders.count
        
        self.findAndRegisterChildCategories()
        self.findAndRegisterChildProperties()
        
        if self.persistors.typeNames != Self.DEFAULT_PERSISTORS.typeNames {
            self._isEmpty = false
        }
        
        @Sendable func attemptWhenLoaded(startTime:Date, attempt:Int = 0) {
            guard attempt < 100 else {
                dlog?.warning("attemptWhenLoaded passed 100 recursions!")
                return
            }
            
            let newProviderCount = self.persistors.count + (self.defaultsProvider != nil ? 1 : 0)
            if self.providersLoadedCount >= allProvidersCount {
                
                let delta = abs(loadStartTime.timeIntervalSinceNow)
                if newProviderCount > allProvidersCount || delta < 0.099 || (Self.DEBUG_IS_SHOULD_DELAY_LOAD && attempt == 0) {
                    var delay : TimeInterval = 0.05
                    if newProviderCount > allProvidersCount {
                        dlog?.warning("[\(self.name)] Providers added after load started! waiting for other providers")
                    } else if Self.DEBUG_IS_SHOULD_DELAY_LOAD == true {
                        dlog?.note("[\(self.name)] Will wait because DEBUG_IS_SHOULD_DELAY_LOAD")
                        delay = max(Self.DEBUG_LOAD_DELAY, 0.05)
                    } else {
                        dlog?.verbose(log:.info, "[\(self.name)] Will wait because too soon (giving a chance to async add settings providers)")
                    }
                    
                    MNExec.exec(afterDelay: delay) {
                        attemptWhenLoaded(startTime: startTime, attempt:attempt + 1)
                    }
                    return
                }
                
                dlog?.verbose("\(self.description) Last persistor loaded. \(allProvidersCount) / \(newProviderCount)")
                
                if delta > 0.05 {
                    Self.notifyLoaded(loadStartTime: loadStartTime, settings: self)
                    self.bootState = .running
                } else {
                    MNExec.exec(afterDelay: delta) {[self, loadStartTime] in
                        Self.notifyLoaded(loadStartTime: loadStartTime, settings: self)
                        self.bootState = .running
                    }
                }
            }
        }
        
        if self.name == Self.DEFAULT_MNSETTINGS_NAME && Self.IS_SHOULD_LOAD_DEFAULT_STD_SETTINGS == false {
            self.lock.withLockVoid {
                self.providersLoadedCount = allProvidersCount
                self.bootState = .running
            }
        } else {
            dlog?.info("load START for \"\(name)\" ")
            self.bootState = .loading;
            allProviders.forEach {[self] pers in
                if let persistor = pers as? MNSettingSaveLoadable {
                    Task {[persistor, self] in
                        dlog?.info("[\(name)] loading persistor: \(persistor)")
                        let count = try await persistor.load(
                            info: ["name":self.name, "class":Self.self])
                        dlog?.verbose(log: .success, "persistor \(persistor) loaded \(count) items.")
                        
                        // if not thrown error - persistor.load is done
                        self.lock.withLockVoid {
                            self.providersLoadedCount += 1
                        }
                        attemptWhenLoaded(startTime: loadStartTime) // when all persistors loaded
                    }
                } else {
                    // Not loadable / savable:
                    self.lock.withLockVoid {
                        self.providersLoadedCount += 1
                    }
                    attemptWhenLoaded(startTime: loadStartTime) // when all persistors loaded
                }
            }
        }
    }
    
    deinit {
        dlog?.info("MNSettings(named:\(name)).deinit")
    }
    
    // MARK: Private
    private var categories : [MNSCategoryName:Weak<MNSettingsCategory>] = [:]
    private var otherCategory : OtherCategory?
    
    var wasChanged : Bool {
        return self.lock.withLock {
            return self.changes.count > 0
        }
    }
    
    var categoryNames : [String] {
        let catNames : [String] = self.categories.keysArray.map { key in
            Self.sanitizeString(key)
        }
        return catNames.sorted()
    }
    
    func setNotEmpty() {
        self._isEmpty = false
    }
    
    fileprivate var isBulkChangingNow : Bool {
        return self._bulkChangeKey.wrappedValue != nil
    }
    
    fileprivate static func notifyLoaded(loadStartTime:Date, settings:MNSettings, depth:Int = 0) {
        let depth = max(0, depth)
        
        var toRemove : [Int] = []
        if depth < 16 && settings.observers.count < settings.allKeys.count {
            dlog?.note("[\(settings.name)] notifyLoaded delayed \(depth)")
            MNExec.exec(afterDelay: 0.05) {[depth, settings] in
                self.notifyLoaded(loadStartTime:loadStartTime, settings:settings, depth: depth + 1)
            }
            return
        }
        
        if MNUtils.debug.IS_DEBUG && dlog != nil {
            let timeDelta = abs(loadStartTime.timeIntervalSinceNow)
            let timeString = "\(timeDelta.toString(decimal: 3)) sec."
            let addStr = (DEBUG_IS_SHOULD_DELAY_LOAD && DEBUG_LOAD_DELAY > 0.09) ? " DEBUG_IS_SHOULD_DELAY_LOAD " : ""
            
            dlog?.info("load END for \"\(settings.name)\". \(addStr)\(timeString)")
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
    
    public static func staticSanitizeKey (_ key:MNSKey, delimiter:String = MNSettings.CATEGORY_DELIMITER)->MNSKey {
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
    
    func sanitizeKey (_ key:MNSKey)->MNSKey {
        var result = Self.sanitizeString(key)
        if Self.IS_SHOULD_USE_ONLY_REG_CATEGORIES {
            let catNames = self.categoryNames
            
            if MNUtils.debug.IS_DEBUG && self.name == Self.standard.name &&  self.values.count > 0 {
                if [1, 2].contains(self.values.count) {
//                    dlog?.info("\(self.name).unreg issue : \(catNames.descriptionsJoined) vals: \(self.values.count)")
//                    for (k, v) in self.values {
//                        dlog?.info("   unreg issue \(self.name). first k/value: k: \"\(k)\" : v: \(v.sortedKeys)")
//                    }
                }
            }
        }

        // For debugging? let category = category(forKey:skey)
        return result
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
    public func categoryName(forKey key : MNSKey, delimiter:String = MNSettings.CATEGORY_DELIMITER)->MNSCategoryName? {
        return Self.categoryName(forKey: key, delimiter: delimiter)
    }
    
    func unregisterObserver(_ observer: AnyMNSettabled) {
        var obsList = self.observers[observer.key] ?? []
        let initialCount = obsList.count
        obsList.removeAll { setbled in
            setbled.key == observer.key && setbled.uuid == observer.uuid
        }
        if MNUtils.debug.IS_DEBUG && dlog != nil {
            if initialCount < obsList.count {
                dlog?.success("\(self.name).unregisterObserver \"\(observer.key)\" ")
            } else {
                dlog?.verbose(log: .fail, "\(self.name).unregisterObserver failed finding \"\(observer.key)\" ")
            }
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
        let key = self.sanitizeKey(settable.key)
        let cat = Self.categoryName(forKey: settable.key) ?? Self.OTHER_CATERGORY_NAME
        if cat == Self.OTHER_CATERGORY_NAME {
            self.createOtherCategoryIfNeeded()
            self.registerCategory(self.otherCategory!)
        }
        dlog?.verbose("[\(self.name)] registerSettable \(key) cat: \(cat) state: \(self.bootState)")
        self.registerValue(settable.wrappedValue, forKey: key)
    }
    
    func unregisterSettable<T:MNSettableValue>(_ settable : MNSettable<T>) {
        let key = self.sanitizeKey(settable.key)
//        if self.name == Self.standard.name {
//            dlog?.info("unreg issue unregisterSettable \(key)")
//        }
        self.unregisterValue(forKey: key)
    }
    
    // MARK: Public
    public static func instance(byName name:String)->MNSettings? {
        var result : MNSettings? = nil
        mnSettings_registryLock.withLock {
            result = mnSettings_registry[name]?.value
        }
        return result
    }
    
    public static func updateRegistry() {
        mnSettings_registryLock.withLock {
            mnSettings_registry = mnSettings_registry.compactMapValues({ aweak in
                return (aweak.value != nil) ? aweak : nil
            })
        }
    }
    
    private var _isEmpty : Bool = true
    public var isEmpty : Bool {
        guard self._isEmpty == false else {
            return true
        }
        
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
        
        let categoryNames = self.categoryNames
        
        if isDebug, let dlogAll = DLog.util["MNSettings"] {
            let tab = "   "
            let tab2 = tab.repeated(times: 2)
            var userDefaultsPersistor : MNUserDefaultsPersistor? = nil
            
            if self.isEmpty {
                dlogAll.info("- instance [\(self.name)] state: .\(self.bootState) is EMPTY!")
            } else {
                dlogAll.info("- instance [\(self.name)] state: .\(self.bootState)")
                if persistors.count > 0 {
                    dlogAll.info(tab + "+ persistors (\(persistors.count)) for [\(self.name)]")
                    for persistor in persistors {
                        dlogAll.info(tab2 + "persistor (\(persistor))")
                        if let pers = (persistor as? MNUserDefaultsPersistor) {
                            userDefaultsPersistor = pers
                        }
                    }
                }
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
                
                if let userDefaultsPersistor = userDefaultsPersistor {
                    let keyPrefix = userDefaultsPersistor.keyPrefix
                    let dict = userDefaultsPersistor.defaultsInstance?.dictionaryRepresentation().filter { k, v in
                        return k.hasPrefix(keyPrefix)
                    } ?? [:]
                    
                    dlogAll.info(tab + "reg userDefaultsPersistor (\(dict.count))")
                    for (k, v) in dict {
                        dlogAll.info(tab2 + "reg k: \(k) v: \("\(v)".replacingOccurrences(of: .newlines, with: " "))")
                    }
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
        
        // dlog?.verbose(">>[5]     unsafeSetValuesIntoPersistors dict:\(dict)")
        
        // We block this thred/loop until the Task asyncs are done:
        let arr = Array(self.persistors)
        let total = arr.count
        if total > 0 {
            dlog?.info(">>[5]     unsafeSetValuesIntoPersistors dict:\(dict)")
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
        } else {
            dlog?.note(">>[5]     unsafeSetValuesIntoPersistors NO PERSISTORS \(dict)")
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
                    self.setNotEmpty()
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
                
                if obsList.count > 0 {
                    self.setNotEmpty()
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
            dlog?.success("\(self.name) unregisterValue \(key) cat: \(cat)")
            vals.removeValue(forKey: key)
            self.lock.withLock {
                if vals.count == 0 {
                    self.values[cat] = nil  // unRegisterValue
                } else {
                    self.values[cat] = vals // unRegisterValue
                }
            }
        } else if false && MNUtils.debug.IS_DEBUG && dlog?.isVerboseActive == true {
            self.lock.withLock {
                dlog?.verbose(log:.fail, "[\(self.name)] unregisterValue failed to find key: \(key) vals: \(self.values) cats: \(self.categories)")
            }
        }
    }
    
    public func registerValue<V : MNSettableValue>(_ value: V, forKey key: MNSKey) {
        do {
            
            if let val: V = try self.getValue(forKey: key), val.hashValue == value.hashValue {
                // Already registered, same value
                return
            }
            dlog?.success("\(self.name).registerValue \"\(key)\" ")
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
    private func createBulkChangesKey()->String {
        return "{\(name).\(Date.now.ISO8601Format())}"
    }
    
    public func asyncBulkChanges(block: @escaping MNSettingsAsyncCompletionBlock) async throws {
        if self.isBulkChangingNow {
            dlog?.warning("\(name) asyncBulkChanges - already changing, will wait.")
        }
        
        let newKey = createBulkChangesKey()
        try await self.lock.withAsyncLock {
            dlog?.verbose("asyncBulkChanges: \(newKey) START")
            self.bulkChangeKey = newKey
            
            // will allow all changes in one lock / unlock bulk and prevent saving while bulk work is in progress
            try await block(self)

            self.bulkChangeKey = nil
            dlog?.verbose("asyncBulkChanges: \(newKey) END")
        }
    }
    
    public func bulkChanges(block: @escaping  MNSettingsCompletionBlock) throws {

        if self.isBulkChangingNow {
            dlog?.warning("\(name) bulkChanges - already changing, will wait.")
        }

        let newKey = createBulkChangesKey()
        try self.lock.withLockVoid {
            dlog?.verbose("bulkChanges: \(newKey) START")
            self.bulkChangeKey = newKey
            
            // will allow all changes in one lock / unlock bulk and prevent saving while bulk work is in progress
            try block(self)

            self.bulkChangeKey = nil
            dlog?.verbose("bulkChanges: \(newKey) END")
        }
    }
    
    public func resetToDefaults() async throws {
        try await self.asyncBulkChanges(block: { settings in
            settings.values = [:]
            settings.changes = []

            // Get all key-values
            let defaults = try await self.defaultsProvider?.fetchAllKeyValues() ?? [:]
            if defaults.count > 0 {
                for persistor in self.persistors {
                    try await persistor.setValuesForKeys(dict: defaults)
                }
                try self.unsafeNotifyObservers(changes: defaults, isDefaults: true, excluding: [])
            } else {
                dlog?.note("{\(self.name)} resetToDefaults - defaultsProvider: \(self.defaultsProvider.descOrNil) failed fetching defaults!")
            }
        })
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
            self.lock.withLock {
                if var vals = self.values[fromCat] {
                    let prev = vals[fromKey]?.description ?? "<nil>"
                    
                    vals[fromKey] = nil
                    if vals.count == 0 {
                        self.values[fromCat] = nil
                    } else {
                        self.values[fromCat] = vals
                    }
                    
                    if !isBoot {
                        self.appendChange(key: fromKey, action: .value, from: prev, to: nil)
                        self.appendChange(key: fromKey, action: .key, from: fromKey, to: nil)
                    }
                }
            }
        }
        
        if let toCat = self.categoryName(forKey: toKey) {
            self.lock.withLock {
                var vals = self.values[toCat] ?? [:]
                vals[toKey] = value // Set new value
                if vals.count == 0 {
                    self.values[toCat] = nil
                } else {
                    self.values[toCat] = vals
                }
                
                if !isBoot {
                    self.appendChange(key: toKey, action: .key, from: nil, to: toKey)
                    self.appendChange(key: toKey, action: .value, from: nil, to: value.description)
                }
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
        dlog?.verbose(">>[2]  valueWasChanged for: \(key) from: \(fromValue) to: \(toValue)")
        // Validate in values
        if let category = self.categoryName(forKey: key) {
            var vals : [MNSKey : AnyMNSettableValue] = [:]
            self.lock.withLock {
                vals = self.values[category] ?? [:]
            }
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
