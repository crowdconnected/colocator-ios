//
//  CCLocationTests.swift
//  CCLocationTests
//
//  Created by Ralf Kernchen on 16/10/2016.
//  Copyright © 2016 Crowd Connected. All rights reserved.
//

import XCTest
import CoreLocation
@testable import CCLocation

class CCLocationTests: XCTestCase {

    let testAPIKey = "iosrtest"
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    class MockCCLocation: CCLocation {
        
        var mockUrlString: String?
        var mockColocatorManger: ColocatorManager?
        
        var lastAliasesMessage: Messaging_ClientMessage?
        
        override func start(apiKey: String, urlString: String? = nil) {
            mockUrlString = apiKey + Constants.DEFAULT_END_POINT_PARTIAL_URL
            if urlString != nil {
                mockUrlString = urlString!
            }
            mockColocatorManger = ColocatorManager()
        }
        
        override func stop() {
            mockColocatorManger = nil
        }
        
        override func getDeviceId() -> String? {
            return UserDefaults.standard.string(forKey: CCSocketConstants.LAST_DEVICE_ID_KEY)
        }
        
        override func setAliases(aliases: Dictionary<String, String>) {
            for key in aliases.keys {
                var aliasMessage = Messaging_AliasMessage()
                aliasMessage.key = key
                aliasMessage.value = aliases[key]!

                lastAliasesMessage = Messaging_ClientMessage()
                lastAliasesMessage?.alias.append(aliasMessage)
            }
        }
    }
    
    func testStartSDK() {
        let mockCCLocation = MockCCLocation()
        let realCCLocation = CCLocation()
        let testAPIKey = "123456"
        
        mockCCLocation.start(apiKey: testAPIKey)
        realCCLocation.start(apiKey: testAPIKey)
        
        let mockURL = mockCCLocation.mockUrlString
        let realURL = realCCLocation.colocatorManager?.ccServerURLString
        
        XCTAssert(mockURL == realURL)
    }
    
    func testStopSDK() {
        let realCCLocation = CCLocation()
        let testAPIKey = "123456"
        
        realCCLocation.start(apiKey: testAPIKey)
        realCCLocation.stop()
        
        let realColocatorManager = realCCLocation.colocatorManager
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 121) {
            let areObjectsDestroyed = realColocatorManager?.ccLocationManager == nil &&
            realColocatorManager?.ccRequestMessaging == nil &&
            realColocatorManager?.ccInertial == nil &&
            realColocatorManager?.ccSocket == nil
            
            XCTAssert(areObjectsDestroyed)
        }
    }
    
    func testGetDeviceID() {
        let mockCCLocation = MockCCLocation()
        let realCCLocation = CCLocation()
        let testAPIKey = "123456"
        
        mockCCLocation.start(apiKey: testAPIKey)
        realCCLocation.start(apiKey: testAPIKey)
        
        let mockDeviceID = mockCCLocation.getDeviceId()
        let realDeviceID = realCCLocation.getDeviceId()
        
        XCTAssert(mockDeviceID == realDeviceID)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
