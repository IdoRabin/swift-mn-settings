//
//  AppSettable.swift
//  Bricks
//
//  Created by Ido on 07/07/2022.
//

import Foundation
import DSLogger
import MNUtils

/*

 protocol AppSettingProvider {
     func noteChange(_ change:String, newValue:Sendable)
     func bulkChanges(block: @escaping  (_ settings : Self) -> Void)
     func resetToDefaults()
     
     var other : [String:Sendable] { get }
     var wasChanged : Bool { get }
     var isLoaded : Bool { get }
 }

 struct BuildType: OptionSet, Codable, Hashable {
     let rawValue: Int
     
     static let debug = BuildType(rawValue: 1 << 0)
     static let production = BuildType(rawValue: 1 << 1)
     
     // All settings
     static let all: BuildType = [.debug, .production]
     
     static var currentBuildType : BuildType {
         if Debug.IS_DEBUG {
             return .debug
         }
         return .production
     }
 }

 protocol AppSettingsContainer {
     func getValueFor(key:String)->(any AppSettableValue)?
     mutating func setValueFor(key:String, value:(any AppSettableValue)?)
 }

 
fileprivate let dlog : DSLogger? = DLog.forClass("AppSettable")

fileprivate weak var appSettings : AppSettings? = nil

protocol AppSettableKind {
    static var valueType : any Any.Type { get }
    var valueType : any Any.Type { get }
}

extension AppSettableKind /* default implementation */ {
    var valueType : any Any.Type {
        return Self.valueType
    }
}

typealias AppSettableValue = Equatable & Codable & Sendable

extension AppSettable : AppSettableKind {
    static var valueType : any Any.Type {
        return T.self
    }
    
    func setValue<TOther>(_ val : TOther) {
        guard let val = val as? T else {
            dlog?.note("AppSettable<\(TOther.self)>.setValue: \(val). failed: Types mismatch: the param value type should be expected as a: \(valueType.self), not \(TOther.self).")
            return
        }
        self.wrappedValue = val as T
    }

    func getValue<TOther>()->TOther? {
        guard T.self == valueType else {
            dlog?.note("AppSettable<\(TOther.self)>.getValue:. failed: Types mismatch: the return value type should be expected as a: \(valueType.self), not \(TOther.self).")
            return nil
        }
        return self.wrappedValue as? TOther
    }
}

// MARK: AppSettable protocol - depends on AppSettings
@propertyWrapper
final class AppSettable<T:AppSettableValue> : Codable {
    nonisolated private let lock = MNLock(name: "\(AppSettable.self)")

    static var settingsInstance : AppSettings? {
        get {
            return appSettings
        }
        set {
            if appSettings != nil {
                dlog?.warning("AppSettable changing the defined AppSettings!")
            }
            appSettings = newValue
        }
    }
    static func setSettingsInstance(instance: AppSettings) {
        if appSettings == nil {
            appSettings = instance
        } else {
            dlog?.warning("AppSettable \(Self.self) | \(self) already has appSettings defined!")
        }
    }
    
    enum CodingKeys : String, CodingKey, CaseIterable {
        case name  = "name"
        case value = "value"
    }
    
    // MARK: properties
    private var _value : T
    @SkipEncodeSendable var name : String = ""
    
    var wrappedValue : T {
        get {
            return lock.withLock {
                return _value
            }
        }
        set {
            lock.withLockVoid {
                let oldValue = _value
                let newValue = newValue
                if newValue != oldValue {
                    _value = newValue
                    let changedKey = name.count > 0 ? "\(self.name)" : "\(self)"
                    AppSettings.shared.noteChange(key:changedKey, newValue: newValue)
                }
            }
        }
    }

    init(name newName:String, `default` defaultValue : T) {
        
        // basic setup:
        self.name = newName
        self._value = defaultValue
        
        AppSettings.registerDefaultValue(key:newName, value:defaultValue)
        guard AppSettings.sharedIsLoaded else {
            return
        }
        
        dlog?.info("ha!!!!! \(newName) : \(defaultValue)")
        self.wrappedValue = defaultValue
        
        // Adv. setup:
//        if let value = AppSettings.shared.getOtherValue(named:"newName") {
//
//        }
//        Task {
//            var newValue : T = defaultValue
//            // dlog?.info("searching for [\(newName)] in \(AppSettings.shared.other.keysArray.descriptionsJoined)")
//            if let loadedVal = await AppSettings.shared.other[newName] as? T {
//                newValue = loadedVal
//                let keys = await AppSettings.shared.other.keysArray.descriptionsJoined
//                dlog?.success("found and set for [\(newName)] in \(keys)")
//            } else {
//                if Debug.IS_DEBUG && AppSettings.shared.other[newName] != nil {
//                    let desc = await AppSettings.shared.other[newName].descOrNil
//                    dlog?.warning("failed cast \(desc) as \(T.self)")
//                }
//
//                // newValue =
//            }
//            return newValue
//        }
//
//        if let newValue = newValue {
//            dlog?.info("Default value [\(self.name)] - setting to \(newValue)")
//            self._value = newValue
//        } else {
//            dlog?.info("Default value [\(self.name)] - NOT FOUND- set \(newValue)")
//        }
    }
    
    // MARK: AppSettable: Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode only whats needed
        self.name = try container.decode(String.self, forKey: .name)
        self._value = try container.decode(T.self, forKey: .value)
    }
    
    // MARK: AppSettable: Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try lock.withLockVoid {
            try container.encode(name,   forKey: .name)
            try container.encode(_value, forKey: .value)
        }
    }
}
*/

/*
 //
 //  AppSettings.swift
 //  Bricks
 //
 //  Created by Ido Rabin on 24/07/2023.
 //  Copyright © 2023 IdoRabin. All rights reserved.
 //
 
 import Foundation
 import DSLogger
 import MNUtils
 import MNVaporUtils
 
 // import Codextended
 
 fileprivate let dlog : DSLogger? = DLog.forClass("AppSettings")?.setting(verbose: true)
 fileprivate let cachedKeys = MNCache<String, String>(name:"AppSettings.KeysCache", maxSize: 1500)
 
 fileprivate extension String /* key for settings */ {
 var asAppSettingsKey : String {
 guard self.count > 0 else {
 dlog?.note("asAppSettingsKey input string is empty (length 0)")
 return self
 }
 
 // Cached key:
 if let cached = cachedKeys[self] {
 return cached
 }
 
 var result = self.replacingOccurrences(ofFromTo: [AppSettings.CHANGE_DELIM : "_"])
 if Debug.IS_DEBUG {
 assert(AppSettings.KEY_DELIM != "_", "AppSettings.KEY_DELIM should not be an underscore!  (nor equal to AppSettings.CHANGE_DELIM)")
 assert(AppSettings.CHANGE_DELIM != "_", "AppSettings.CHANGE_DELIM should not be an underscore!  (nor equal to AppSettings.KEY_DELIM)")
 assert(AppSettings.KEY_DELIM != AppSettings.CHANGE_DELIM, "AppSettings.KEY_DELIM should not be an underscore!  (nor equal to AppSettings.CHANGE_DELIM)")
 
 
 if result.components(separatedBy: AppSettings.CHANGE_DELIM).count == 0 {
 dlog?.note("asAppSettingsKey input string has no delimiters?")
 }
 if result.components(separatedBy: "_").count == 0 {
 dlog?.note("asAppSettingsKey input string has no delimiters?")
 }
 }
 result = result.camelCaseToSnakeCase(delimiter: AppSettings.KEY_DELIM)
 let parts = result.components(separatedBy: AppSettings.KEY_DELIM)
 if !AppSettings.ALL_CODING_KEYS_STRS.contains(elementEqualTo: parts.first ?? ">>!__this_string_is_assumed_to_never_equal_any_of_ther_AppSettings_coding_keys__!<<") {
 // This key has no prefix for any given "coding key" - we add "other" and assume that is what was meant:
 result = AppSettings.CodingKeys.other.rawValue + AppSettings.KEY_DELIM + result
 }
 
 // Save to cache:
 cachedKeys[self] = result
 if self != result {
 dlog?.verbose("key: from: \(self) => \(result)")
 }
 
 return result
 }
 }
 // A singleton for all app settingsåå, saves and loads from a json file the last saved settings.
 // "Other" are all settings properties that are distributed around the app as properties of other classes. They åare still connected and saved into this settings file, under the "other" dictionary.
 // AppSettingProvider
 final class AppSettings : JSONFileSerializable {
 
 typealias AppSettingsOther = [String : any AppSettableValue]
 
 #if VAPOR
 static let FILENAME = AppConstants.BSERVER_APP_SETTINGS_FILENAME
 #else
 static let FILENAME = AppConstants.CLIENT_SETTINGS_FILENAME
 #endif
 
 static let CHANGE_DELIM = "|"
 static let KEY_DELIM = "." // delimiter within each key to describe the "hirarchy"/"depth"/"nesting level" of the setting
 static let ALL_CODING_KEYS_STRS = CodingKeys.allCases.rawValues.lowercased // for optimization we have the array "cahced" so to speak...
 
 // MARK: Const
 enum CodingKeys: String, CodingKey, CaseIterable {
 case global = "global"
 case server = "server"
 case client = "client"
 case stats  = "stats"
 case debug  = "debug"
 case other  = "other"
 
 static func codingKey(for str:String)->CodingKeys? {
 let prx = str.asAppSettingsKey.components(separatedBy: AppSettings.KEY_DELIM).first ?? str.lowercased()
 if let enumKey = CodingKeys(stringValue: prx) {
 return self.allCases.first { akey in
 akey == enumKey
 }
 } else {
 return nil
 }
 }
 
 static func isString(_ str:String, ofKey key:CodingKeys)->Bool {
 guard let codingKey = self.codingKey(for: str) else {
 return false
 }
 
 return codingKey == key
 }
 
 static func isOther(key:String)->Bool {
 return isString(key, ofKey: .other)
 }
 }
 
 // MARK: Static
 static var _isLoaded : Bool = false
 static var _initingShared : Bool = false
 static var _defaultResponWithReqId = Dictionary<BuildType, Bool>(uniqueKeysWithValues:[(BuildType.all, true)])
 static var _defaultResponWithSelfUserId = Dictionary<BuildType, Bool>(uniqueKeysWithValues:[(BuildType.all, true)])
 static var _defaultParamKeysToNeverRedirect : [String] = ["password", "pwd", "email", "phoneNr", "phoneNumber" ,"phone", "token",
 "accessToken", "user"]
 
 // MARK: Private Properties / members
 @SkipEncode private var _lock = MNLock(name: "\(AppSettings.self)")
 @SkipEncode private var _changes : [String] = []
 @SkipEncode private var _bootState : MNBootState = .booting
 @SkipEncode private var _isBlockChanges : Bool = false
 
 // MARK: Public Properties / members
 var global : AppSettingsGlobal
 var client : AppSettingsClient?
 var server : AppSettingsServer?
 var stats : AppSettingsStats
 var debug : AppSettingsDebug?
 
 /// It is reccommended not to access these values directly, but only via the corresponding @AppSettable wrappers
 var other: AppSettingsOther = [:]
 private static var defaultValues : AppSettingsOther = [:]
 
 var wasChanged : Bool {
 return _changes.count > 0
 }
 
 static var isLoaded : Bool {
 guard let ashared = self._shared else {
 return false
 }
 return ashared.isLoaded
 }
 
 var isLoaded : Bool {
 return ![MNBootState.booting, MNBootState.loading].contains(self._bootState)
 }
 
 static var sharedIsLoaded : Bool {
 guard let ashared = _shared else {
 return false
 }
 return ashared.isLoaded
 }
 
 // MARK: Lifecycle
 static private func pathToSettingsFile()->URL? {
 guard var path = FileManager.default.urls(for: FileManager.SearchPathDirectory.applicationSupportDirectory,
 in: FileManager.SearchPathDomainMask.userDomainMask).first else {
 return nil
 }
 
 // App Name:
 let appName = Bundle.main.bundleName?.capitalized.replacingOccurrences(of: .whitespaces, with: "_") ?? "Bundle.main.bundleName == nil !"
 path = path.appendingPathComponent(appName)
 
 // Create folder if needed
 if !FileManager.default.fileExists(atPath: path.absoluteString) {
 do {
 try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
 } catch let error {
 dlog?.warning("pathToSettingsFile failed crating /\(appName)/ folder. error: " + error.localizedDescription)
 return nil
 }
 }
 
 path = path.appendingPathComponent(self.FILENAME).appendingPathExtension("json")
 return path
 }
 
 static func registerDefaultValue(key:String, value:any AppSettableValue) {
 dlog?.verbose("registerDefaultValue [\(key)] = \(value)")
 defaultValues[key] = value
 }
 
 @SkipEncode private static var _shared : AppSettings? = nil
 public static func shared<T:Any>(_ block : (_ appSettings : AppSettings)->T?)->T? {
 guard let sharedInst = _shared else {
 dlog?.warning("shared<T:Any>(_ block:()->T) shared instance is nil!")
 return nil
 }
 
 return sharedInst.blockChanges(block: block)
 }
 
 // MARK: Singleton
 public static var shared : AppSettings {
 Self._initingShared = true
 var wasNewed = false
 if let _shared = _shared {
 return _shared
 } else if let fileURL = Self.pathToSettingsFile() {
 let loadResult : Result<AppSettings, Error> = AppSettings.loadFromJSON(fileURL)
 switch loadResult {
 case .success(let loaded):
 _shared = loaded
 dlog?.verbose(log:.success, "Init as: loaded from:\(fileURL.lastPathComponent)")
 wasNewed = true
 case .failure(let error):
 dlog?.note("Failed loading from file: \(error.description)")
 }
 }
 
 if _shared == nil {
 dlog?.verbose(log:.success, "Init as: defaults")
 _shared = AppSettings()
 wasNewed = true
 }
 
 if wasNewed {
 AppSettable<String /* Generic type doesnt matter */>.setSettingsInstance(instance: _shared!)
 self.registerIffyCodables()
 }
 
 return _shared!
 }
 
 private static var isServerApp : Bool {
 #if VAPOR
 return true
 #else
 return false
 #endif
 }
 
 private init() {
 _bootState = .booting
 self.global = AppSettingsGlobal()
 self.client = Self.isServerApp ? nil : AppSettingsClient()
 self.server = Self.isServerApp ? AppSettingsServer() : nil
 self.stats = AppSettingsStats()
 self.debug = AppSettingsDebug()
 self.other = [:]
 _bootState = .running
 }
 
 // MARK: Public
 static private func registerIffyCodables() {
 
 // Client:
 #if !VAPOR
 StringAnyDictionary.registerClass(PreferencesVC.PreferencesPage.self)
 #endif
 
 // Server:
 #if VAPOR
 //          StringAnyDictionary.registerClass(?? .... )
 #endif
 
 // All Builds:
 StringAnyDictionary.registerType([String:String].self) // see UnkeyedEncodingContainerEx
 }
 
 // MARK: Codable
 public func encode(to encoder: Encoder) throws {
 guard [.running, .saving].contains(_bootState) else {
 throw MNError(code:.misc_failed_saving, reason: "encode(to encoder) cannot take place while boot state == \(_bootState)")
 }
 let pre = self._bootState
 _bootState = .saving
 var container = encoder.container(keyedBy: CodingKeys.self)
 try container.encode(global, forKey: CodingKeys.global)
 try container.encodeIfPresent(client, forKey: CodingKeys.client)
 try container.encodeIfPresent(server, forKey: CodingKeys.server)
 try container.encode(stats, forKey: CodingKeys.stats)
 try container.encode(debug, forKey: CodingKeys.debug)
 // TODO: try container.encode(other, forKey: CodingKeys.other)
 _bootState = (pre != .saving) ? pre : .running
 }
 
 public init(from decoder: Decoder) throws {
 _bootState = .loading
 let keyed = try decoder.container(keyedBy: CodingKeys.self)
 self.global = try keyed.decode(AppSettingsGlobal.self, forKey: CodingKeys.global)
 self.client = try keyed.decodeIfPresent(AppSettingsClient.self, forKey: CodingKeys.client)
 self.server = try keyed.decodeIfPresent(AppSettingsServer.self, forKey: CodingKeys.server)
 self.stats = try keyed.decode(AppSettingsStats.self, forKey: CodingKeys.stats)
 self.debug = try keyed.decode(AppSettingsDebug.self, forKey: CodingKeys.debug)
 // TODO: self.other = try keyed.decode(AppSettingsOther.self, forKey: CodingKeys.other)
 _bootState = .running
 }
 
 // MARK: AppSettingProvider
 func AppSettingsContainerForKey(key: String)->(CodingKeys, AppSettingsContainer)? {
 guard let ckey = CodingKeys.codingKey(for: key) else {
 return nil
 }
 var container : AppSettingsContainer? = nil
 switch ckey {
 case .global: container = self.global
 case .server: container = self.server
 case .client: container = self.client
 case .stats : container = self.stats
 case .debug : container = self.debug
 case .other : container = self.other
 }
 
 if let container = container {
 return (ckey, container)
 }
 return nil
 }
 
 func validateKey(key: String, hasValue value: any AppSettableValue)->Bool {
 let asKey = key.asAppSettingsKey
 if let ckey = CodingKeys.codingKey(for: asKey) {
 var result = false
 if let tuple = AppSettingsContainerForKey(key: asKey) {
 dlog?.success("Fetching value for key: \(asKey) @ .\(ckey.rawValue)")
 let savedValue = tuple.1.getValueFor(key: asKey)
 dlog?.success("Found        saved key: \(asKey) @ .\(ckey.rawValue) == \(savedValue.descOrNil)")
 }
 // ============================= rododo TODO: ==============
 //            switch ckey {
 //            case .global, .server, .client, .stats, .debug:
 //
 //            case .other:
 //                let val = other[asKey]
 //                return val == value
 //            }
 }
 return false
 }
 
 func noteChange(key: String, newValue: any AppSettableValue) {
 let asKey = key.asAppSettingsKey
 let change = "\(asKey.asAppSettingsKey)\(Self.CHANGE_DELIM)\(newValue)"
 self._changes.append(change)
 if Debug.IS_DEBUG {
 
 // TODO: Temp remove next line
 self.validateKey(key: "server.check.this.value", hasValue: "21")
 
 // Make sure the value was actually changed in the settings:
 if !self.validateKey(key: asKey, hasValue: newValue) {
 dlog?.warning("noteChange(key: String, newValue: Any) failed validating that the value is as expected!")
 }
 }
 }
 
 func blockChanges<T:Any>(block: (AppSettings) -> T?)->T? {
 let result = _lock.withLock {
 return block(self)
 }
 do {
 try self.saveIfNeeded()
 } catch let error {
 dlog?.note("Failed saving after block changes with error: \(error.description)")
 }
 return result
 }
 
 func resetToDefaults() {
 dlog?.verbose("Resetting to defaults")
 _bootState = .booting
 self.global = AppSettingsGlobal()
 self.client = Self.isServerApp ? nil : AppSettingsClient()
 self.server = Self.isServerApp ? AppSettingsServer() : nil
 self.stats = AppSettingsStats()
 self.debug = AppSettingsDebug()
 self.other = [:]
 _bootState = .running
 }
 
 @discardableResult
 func saveIfNeeded() throws -> Bool {
 guard self.wasChanged else {
 return false
 }
 return try self.save()
 }
 
 @discardableResult
 func save() throws -> Bool {
 guard .running == _bootState else {
 throw MNError(code:.misc_failed_saving, reason: "save() cannot take place while boot state == \(_bootState)")
 // return false
 }
 let pre = self._bootState
 _bootState = .saving
 switch self.saveToJSON(Self.pathToSettingsFile()!, prettyPrint: Debug.IS_DEBUG) {
 case .success:
 dlog?.verbose(log: .success, "save() success!")
 return true
 case .failure(let error):
 dlog?.note("save() failed with error: \(error.description)")
 _bootState = pre
 throw error
 }
 }
 
 // MARK: Types
 class AppSettingsGlobal : AppSettableClassContainer {
 // NOTE: All keys must begin with the .global coding key's string:
 @AppSettable(name:"global.newUsernameAllowedTypes", default:MNUserPIITypeSet.allCases) var newUsernameAllowedTypes : MNUserPIITypeSet
 @AppSettable(name:"global.existingAllowedTypes", default:MNUserPIITypeSet.allCases) var existingUsernameAllowedTypes : MNUserPIITypeSet
 }
 
 class AppSettingsClient : AppSettableClassContainer {
 // NOTE: All keys must begin with the .client coding key's string:
 @AppSettable(name:"client.allowsAnalyze", default:true) var allowsAnalyze : Bool
 @AppSettable(name:"client.showsSplashScreenOnInit", default:true) var showsSplashScreenOnInit : Bool
 @AppSettable(name:"client.splashScreenCloseBtnWillCloseApp", default:true) var splashScreenCloseBtnWillCloseApp : Bool
 @AppSettable(name:"client.tooltipsShowKeyboardShortcut", default:true) var tooltipsShowKeyboardShortcut : Bool
 }
 
 class AppSettingsServer : AppSettableClassContainer {
 // NOTE: All keys must begin with the .server coding key's string:
 @AppSettable(name:"server.requestCount", default:0) var requestCount : UInt64
 @AppSettable(name:"server.requestSuccessCount", default:0) var requestSuccessCount : UInt64
 @AppSettable(name:"server.requestFailCount", default:0) var requestFailCount : UInt64
 @AppSettable(name:"server.respondWithRequestUUID", default:AppSettings._defaultResponWithReqId) var respondWithRequestUUID : Dictionary<BuildType, Bool>
 @AppSettable(name:"server.respondWithSelfUserUUID", default:AppSettings._defaultResponWithSelfUserId) var responWithSelfUserUUID : Dictionary<BuildType, Bool>
 
 // Params that the server should NEVER redirect from one endpoint / page to another:
 @AppSettable(name:"server.paramKeysToNeverRedirect", default:AppSettings._defaultParamKeysToNeverRedirect) var paramKeysToNeverRedirect : [String]
 
 var isShouldRespondWithRequestUUID : Bool {
 return respondWithRequestUUID[BuildType.currentBuildType] ?? true == true
 }
 var isShouldRespondWithSelfUserUUID : Bool {
 return responWithSelfUserUUID[BuildType.currentBuildType] ?? true == true
 }
 }
 
 class AppSettingsStats : AppSettableClassContainer {
 // NOTE: All keys must begin with the .stats coding key's string:
 @AppSettable(name:"stats.launchCount", default:0) var launchCount : Int
 @AppSettable(name:"stats.firstLaunchDate", default:Date()) var firstLaunchDate : Date
 @AppSettable(name:"stats.lastLaunchDate", default:Date()) var lastLaunchDate : Date
 }
 
 class AppSettingsDebug : AppSettableClassContainer {
 // NOTE: All keys must begin with the .debug coding key's string:
 
 // All default values should be production values.
 @AppSettable(name:"debug.isSimulateNoNetwork", default:false) var isSimulateNoNetwork : Bool
 }
 }
 
 // We want AppSettingsOther dictionary to conform to the AppSettingsContainer protocol:
 extension AppSettings.AppSettingsOther : AppSettingsContainer {
 func getValueFor(key: String) -> (any AppSettableValue)? {
 return self[key.asAppSettingsKey]
 }
 
 mutating func setValueFor(key: String, value: (any AppSettableValue)?) {
 self[key.asAppSettingsKey] = value
 }
 }
 
 // We want
 class AppSettableClassContainer : Codable, AppSettingsContainer {
 
 func getValueFor(key: String) -> (any AppSettableValue)? {
 // Get from cache:
 
 // Iterate props and save to cache
 let m = Mirror(reflecting: self)
 for child : Mirror.Child in m.children {
 if let label = child.label {
 if let askind = child.value as? AppSettableKind {
 let aType = askind.valueType
 dlog?.info("getValueFor(key: \(key)) label: \(label) sKind: <\(aType)>")
 } else {
 dlog?.note("\(Self.self) property: \(label) is not of AppSettableKind.")
 }
 }
 }
 
 //let res = m.children.first { $0.label == key }
 //dlog?.info("getValueFor(key:\()")
 
 // Return value
 return nil // res as? (any AppSettableValue)
 }
 
 func setValueFor(key: String, value: (any AppSettableValue)?) {
 
 }
 }
 
 /*
  protocol PropertyReflectable { }
  
  extension PropertyReflectable {
  subscript(key: String) -> Any? {
  let m = Mirror(reflecting: self)
  return m.children.first { $0.label == key }?.value
  }
  }*/
 
 /*
  final class AppSettings : AppSettingProvider, JSONFileSerializable {
  
  
  // MARK: Private
  
  internal static func noteChange(_ change:String, newValue:AnyCodable) {
  AppSettings.shared.noteChange(change, newValue:newValue)
  }
  
  fileprivate func resetChangesRecord() {
  self._changes.removeAll(keepingCapacity: true)
  }
  
  // MARK: Public
  func noteChange(_ change:String, newValue:Any) {
  dlog?.verbose("changed: \(change) = \(newValue)")
  _changes.append(change + " = \(newValue)")
  
  guard self.isLoaded else {
  return
  }
  
  // "Other" are all settings properties that are distributed around the app as properties of other classes. They are still connected and saved into this settings file, under the "other" dictionary.
  if CodingKeys.isOther(key: change) {
  other[change] = newValue
  }
  
  // debounce
  // TimedEventFilter.shared.filterEvent(key: "AppSettings.changes", threshold: 0.3, accumulating: change) { changes in
  TimedEventFilter.shared.filterEvent(key: "AppSettings.changes", threshold: 0.2) {
  if self._changes.count > 0 {
  dlog?.verbose("changed: \(self._changes.descriptionsJoined)")
  
  // Want to save all changes to settings into a seperate log?
  // Do it here! - use self._changes
  
  self.saveIfNeeded()
  }
  }
  }
  
  func blockChanges(block:(_ settingsProvider : AppSettingProvider)->Void) {
  self._isBlockChanges = true
  block(self)
  self._isBlockChanges = false
  self.saveIfNeeded()
  }
  
  func resetToDefaults() {
  self.global.existingUsernameAllowedTypes = UsernameType.allActive
  self.global.newUsernameAllowedTypes = UsernameType.allActive
  self.saveIfNeeded()
  }
  
  @discardableResult func saveIfNeeded()->Bool {
  if self.wasChanged && self.save() {
  return true
  }
  return false
  }
  
  @discardableResult
  func save()->Bool {
  if let path = Self.pathToSettingsFile() {
  let isDidSave = self.saveToJSON(path, prettyPrint: Debug.IS_DEBUG).isSuccess
  UserDefaults.standard.synchronize()
  dlog?.successOrFail(condition: isDidSave, "Saving settings")
  if isDidSave {
  if self._changes.count == 0 {
  dlog?.note("Saved settings with NO CHANGES on record!")
  }
  self.resetChangesRecord()
  }
  
  return isDidSave
  }
  return false
  }
  
  // MARK: Singleton
  private static var _shared : AppSettings? = nil
  public static var shared : AppSettings {
  var result : AppSettings? = nil
  
  if let shared = _shared {
  return shared
  } else if let path = pathToSettingsFile() {
  
  if !_initingShared {
  _initingShared = true
  
  Self.registerIffyCodables()
  
  //  Find setings file in app folder (icloud?)
  let res = Self.loadFromJSON(path)
  
  switch res {
  case .success(let instance):
  result = instance
  Self._isLoaded = true
  Self._initingShared = false
  dlog?.success("loaded from: \(path.absoluteString) other: \(instance.other.keysArray.descriptionsJoined)")
  case .failure(let error):
  let appErr = AppError(error: error)
  dlog?.fail("Failed loading file, will create new instance. error:\(appErr) path:\(path.absoluteString)")
  // Create new instance
  result = AppSettings()
  _ = result?.saveToJSON(path, prettyPrint: Debug.IS_DEBUG)
  }
  } else {
  dlog?.warning(".shared Possible timed recursion! stack: " + Thread.callStackSymbols.descriptionLines)
  }
  }
  
  _shared = result
  return result!
  }
  
  private init() {
  _isLoading = false
  
  #if VAPOR
  server = AppSettingsServer()
  client = nil
  #else
  client = AppSettingsClient()
  server = nil
  #endif
  
  global = AppSettingsGlobal()
  stats = AppSettingsStats()
  debug = Debug.IS_DEBUG ? AppSettingsDebug() : nil
  
  // rest to defaults:
  if Debug.RESET_SETTINGS_ON_INIT {
  self.resetToDefaults()
  }
  
  dlog?.info("Init \(String(memoryAddressOf: self))")
  }
  
  deinit {
  dlog?.info("deinit \(String(memoryAddressOf: self))")
  }
  
  // MARK: Codable
  func encode(to encoder: Encoder) throws {
  var cont = encoder.container(keyedBy: CodingKeys.self)
  
  // Save depending on different condition:
  if SettingsEnv.currentEnv == .server {
  try cont.encode(server, forKey: CodingKeys.server)
  }
  if SettingsEnv.currentEnv == .client {
  try cont.encode(client, forKey: CodingKeys.client)
  }
  
  // Save for all builds
  try cont.encode(global, forKey: CodingKeys.global)
  try cont.encode(stats, forKey: CodingKeys.stats)
  
  if Debug.IS_DEBUG {
  try cont.encode(debug, forKey: CodingKeys.debug)
  }
  
  if other.count > 0 {
  var sub = cont.nestedUnkeyedContainer(forKey: .other)
  try sub.encode(dic: other, encoder:encoder)
  }
  }
  
  required init(from decoder: Decoder) throws {
  _isLoading = true
  dlog?.verbose("loading from decoder:")
  
  Self._isLoaded = false
  _changes = []
  debug = nil
  
  let values = try decoder.container(keyedBy: CodingKeys.self)
  
  // Decode depending on different conditions:
  if SettingsEnv.currentEnv == .server {
  server = try values.decodeIfPresent(AppSettingsServer.self, forKey: CodingKeys.server)
  } else {
  server = nil
  }
  
  if SettingsEnv.currentEnv == .client {
  client = try values.decodeIfPresent(AppSettingsClient.self, forKey: CodingKeys.client)
  } else {
  client = nil
  }
  
  // Decode always:
  global = try values.decode(AppSettingsGlobal.self, forKey: CodingKeys.global)
  stats = try values.decode(AppSettingsStats.self, forKey: CodingKeys.stats)
  if Debug.IS_DEBUG {
  debug = try values.decodeIfPresent(AppSettingsDebug.self, forKey: CodingKeys.debug) ?? AppSettingsDebug()
  }
  
  if values.allKeys.contains(.other) {
  var sub = try values.nestedUnkeyedContainer(forKey: .other)
  let strAny = try sub.decodeStringAnyDict(decoder: decoder) // parse the saved string/s into a k-v dictionary
  if Debug.IS_DEBUG && sub.count != strAny.count {
  dlog?.note("Failed decoding some StringLosslessConvertible. SUCCESSFUL keys: \(strAny.keysArray.descriptionsJoined). Find which key is missing.")
  }
  for (key, val) in strAny {
  if let val = val as? AnyCodable {
  other[key] = val
  }
  }
  }
  
  DispatchQueue.main.asyncAfter(delayFromNow: 0.05) {
  self._isLoading = false
  dlog?.success("loaded from decoder")
  }
  }
  }
  
  */
  */
