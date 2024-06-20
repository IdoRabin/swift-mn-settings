import XCTest
<<<<<<< HEAD:Tests/MNSettings2Tests/MNSettings2Tests.swift
@testable import MNSettings2
import DSLogger
=======
@testable import MNSettings
import Logging
>>>>>>> 4d1594ac075be248f31cb914a0635bea69b10561:Tests/MNSettingsTests/MNSettingsTests.swift
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("AppSettingsTest")?.setting(verbose: true)

class AppSettings : MNSettings {
    class AppCategory1 : MNSettingsCategory {
        
    }
    class AppCategory2 : MNSettingsCategory {
        
    }
    let category1 = AppCategory1()
    let category2 = AppCategory2()
    var category3 : AppCategory3!
    var category4 : AppCategory4? = nil
    var x : Int = 1
    var y : String = "y"
    
    override init(key: MNSKey? = nil) {
        self.category3 = AppCategory3(parentKeys: nil)
        super.init(key: key)
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

class AppCategory4 : MNSettingsCategory {
    
}

class AppCategory3 : MNSettingsCategory {
    
}

final class MNSettings2Tests: XCTestCase {

    let appSettings = AppSettings()
    
    override func setUp() {
        appSettings.category4 = AppCategory4(key: "AppCategory4Four")
    }
    
    override func tearDown() {
    }
    
    func testSettings() throws {
        let expectation = XCTestExpectation(description: "delay test")
        MNExec.exec(afterDelay: 1.0) {
            if self.appSettings.bootState == .running {
                expectation.fulfill()
            } else {
                dlog?.note("AppSettings is still: \(self.appSettings.bootState)")
            }
        }
        wait(for: [expectation], timeout: 1.5)
    }
    
    /*
    class AppStats : MNSettingsCategory {
        @MNSettable(key: "launchCount", default: 99) var launchCount
        
        class Local : MNSettingsCategory {
            @MNSettable(key: "llaunchCount", default: 1) var llaunchCount
        }
        
        let local = Local()
    }
    
    let dlog : Logger? = Logger(label:"MNSettingsTests") 
    var settings : MNSettings?
    var stats : AppStats?
    @MNSettable(forSettingsNamed: "testSettings", key: "no_cat_count", default: 5) var noCategoryCount
    
    override func setUp() {
        MNUtils.debug.IS_DEBUG = true
        let persistors : [MNSettingsPersistor] = [
            MNLocalJSONPersistor(name: "testSettings"),
            MNUserDefaultsPersistor(.standard)
        ]
        settings = MNSettings(named: "testSettings", persistors: persistors)
        stats = AppStats()// settings: settings)
    }
    
    override func tearDown() {
        settings = nil
    }
    
    func testSettings() throws {
        let logPrfx = "XCTest testSettings"
        dlog?.info("\(logPrfx) START")
        let expectation = XCTestExpectation(description: "delay test")
        MNExec.exec(afterDelay: 2.5) {[self, settings] in // , dlog
            dlog?.info("\((logPrfx)) [\((settings?.name).descOrNil)] END")
            expectation.fulfill()
        }
        
        let stdrtSettings = MNSettings.standard
        MNExec.exec(afterDelay: 0.15) {[self, stdrtSettings] in // , dlog
            stdrtSettings.debugLogAll()
            self.settings?.debugLogAll()
            // dlog?.info("\((logPrfx)) will change an MNSettable item [launchCount] <<")
            stats?.launchCount += 1
            // dlog?.info("\((logPrfx)) DID change an MNSettable item  [launchCount] <<")
        }
        
        // Exec afer delay
        MNExec.exec(afterDelay: 0.8) {[self, settings] in
            if let key = stats?.$launchCount?.key {
                do {
                    let getVal1 : Int? = try settings?.getValue(forKey: key)
                    if let getVal1 = getVal1 {
                        dlog?.success("\((logPrfx)) getValue from settings: \(getVal1.description) <<")
                    } else {
                        dlog?.notice("\((logPrfx)) getVal FAILED getting value from settings forKey:\(key)")
                    }
                    
                    Task {
                        if let getVal2 : Int = try await settings?.fetchValueFromPersistors(forKey: key) {
                            dlog?.success("\((logPrfx)) fetch Value from persistors: \(getVal2.description) <<")
                            if getVal2 != getVal1 {
                                dlog?.notice("\((logPrfx)) getVal FAILED getting value. getVal2 != getVal1 \(getVal1.descOrNil) != \(getVal2)")
                            }
                        } else {
                            dlog?.notice("\((logPrfx)) getVal FAILED getting value from persistors forKey:\(key)")
                        }
                    }
                } catch let error {
                    dlog?.notice("\((logPrfx)) getVal FAILED getting value. error: \(error)")
                    expectation.fulfill()
                }
            }
        }
        wait(for: [expectation], timeout: 3)
    }
     */
}
