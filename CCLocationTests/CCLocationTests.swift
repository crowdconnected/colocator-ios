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
    let stagingWrongURL = "staging.colocator.net:443/wrongURLString"
    
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
        let expectation = XCTestExpectation(description: "Data should be saved in database if cannot be sent")
        let mockCCLocation = MockCCLocation()
        let realCCLocation = CCLocation.sharedInstance

        realCCLocation.stop()
        
        mockCCLocation.start(apiKey: testAPIKey)
        realCCLocation.start(apiKey: testAPIKey)

        let mockURL = mockCCLocation.mockUrlString
        let realURL = realCCLocation.colocatorManager?.ccRequestMessaging?.ccSocket?.ccWebsocketBaseURL

        mockCCLocation.stop()
        realCCLocation.stop()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            
            XCTAssert(realURL?.contains(mockURL!) ?? false)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.5)
    }
    
    func testStopSDK() {
        let expectation = XCTestExpectation(description: "All objects in Colocator Manager should be removed after stopping the SDK")
        
        let realCCLocation = CCLocation.sharedInstance
        
        realCCLocation.start(apiKey: testAPIKey)
        realCCLocation.stop()
        
        let realColocatorManager = realCCLocation.colocatorManager
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let areObjectsDestroyed = realColocatorManager?.ccLocationManager == nil &&
            realColocatorManager?.ccRequestMessaging == nil &&
            realColocatorManager?.ccInertial == nil &&
            realColocatorManager?.ccSocket == nil
            
            XCTAssert(areObjectsDestroyed)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testGetDeviceID() {
        let mockCCLocation = MockCCLocation()
        let realCCLocation = CCLocation.sharedInstance

        mockCCLocation.start(apiKey: testAPIKey)
        realCCLocation.start(apiKey: testAPIKey)

        let mockDeviceID = mockCCLocation.getDeviceId()
        let realDeviceID = realCCLocation.getDeviceId()

        mockCCLocation.stop()
        realCCLocation.stop()

        XCTAssert(mockDeviceID == realDeviceID)
    }
    
    func testSavingDataInDatabase() {
        let expectation = XCTestExpectation(description: "Data should be saved in database if cannot be sent")
        
        let cclocation = CCLocation.sharedInstance
        cclocation.start(apiKey: testAPIKey, urlString: stagingWrongURL)

        let colocatorManager = cclocation.colocatorManager
        let ccRequestMessages = colocatorManager?.ccRequestMessaging

        let initialMessagesCount = ccRequestMessages?.getMessageCount() ?? 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            cclocation.sendMarker(message: "Test marker 1")
            cclocation.sendMarker(message: "Test marker 2")
            cclocation.sendMarker(message: "Test marker 3")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let finalMessagesCount = ccRequestMessages?.getMessageCount() ?? 0
            
            XCTAssert(initialMessagesCount < finalMessagesCount)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testDatabaseMaximumCapacity() {
        let expectation = XCTestExpectation(description: "Database should store items up to 100.000")
        
        let cclocation = CCLocation.sharedInstance
        cclocation.start(apiKey: testAPIKey, urlString: stagingWrongURL)

        let colocatorManager = cclocation.colocatorManager
        let ccRequestMessages = colocatorManager?.ccRequestMessaging

        let messagesToInsert = 100100

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            colocatorManager?.deleteDatabaseContent()
            
            for i in 0..<messagesToInsert {
                ccRequestMessages?.processStep(date: Date(), angle: Double(i))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 100) {
            let finalMessagesCount = ccRequestMessages?.getMessageCount() ?? 0
            cclocation.stop()
            
            XCTAssert(finalMessagesCount > 99990 && finalMessagesCount < messagesToInsert)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 102)
    }
    
    func testSendDataInOrder() {
        let expectation = XCTestExpectation(description: "Data should be sent in order to server")
        
        let cclocation = CCLocation.sharedInstance
        cclocation.start(apiKey: testAPIKey, urlString: stagingWrongURL)

        let colocatorManager = cclocation.colocatorManager
        let ccRequestMessages = colocatorManager?.ccRequestMessaging

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ccRequestMessages?.processStep(date: Date(), angle: 1)
            ccRequestMessages?.processStep(date: Date(), angle: 2)
            ccRequestMessages?.processStep(date: Date(), angle: 3)
            ccRequestMessages?.processStep(date: Date(), angle: 4)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let finalMessagesCount = ccRequestMessages?.getMessageCount() ?? 0

            if finalMessagesCount > 0 {
                let tempMessageData = ccRequestMessages?.popMessagesFromLocalDatabase(maxMessagesToReturn: 10)

                var subMessageCounter = 0
                var compiledClientMessage = Messaging_ClientMessage()
                let backToQueueMessages = Messaging_ClientMessage()

                if let unwrappedTempMessageData = tempMessageData {
                    for tempMessage in unwrappedTempMessageData {

                        let (newSubMessageCounter,
                             newCompiledClientMessage,
                             _) = ccRequestMessages?.handleMessageType(message: tempMessage,
                                                                               subMessageInitialNumber: subMessageCounter,
                                                                               compiledMessage: compiledClientMessage,
                                                                               queueMessage: backToQueueMessages)
                                                        ?? (subMessageCounter,
                                                            Messaging_ClientMessage(),
                                                            Messaging_ClientMessage())

                        subMessageCounter = newSubMessageCounter
                        compiledClientMessage = newCompiledClientMessage
                    }
                }

                let sortedMessages = compiledClientMessage.step.sorted { (msg1, msg2) -> Bool in
                    msg1.angle < msg2.angle
                }

                cclocation.stop()
                XCTAssert(compiledClientMessage.step == sortedMessages)
                expectation.fulfill()
            } else {
                cclocation.stop()
                XCTAssert(false)
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 3.0)
    }
    
    // connection available
    func testRadioSilence0() {
        let expectation = XCTestExpectation(description: "Data shouldn't be collected in database anymore, but sent immediately")
        
        let cclocation = CCLocation.sharedInstance
        cclocation.start(apiKey: testAPIKey)

        let colocatorManager = cclocation.colocatorManager
        let ccRequestMessages = colocatorManager?.ccRequestMessaging
        
        let initialMessagesCount = ccRequestMessages?.getMessageCount() ?? 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ccRequestMessages?.stateStore.dispatch( TimeBetweenSendsTimerReceivedAction(timeInMilliseconds: 0))
            
            cclocation.sendMarker(message: "Test marker 1")
            cclocation.sendMarker(message: "Test marker 2")
            cclocation.sendMarker(message: "Test marker 3")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let finalMessagesCount = ccRequestMessages?.getMessageCount() ?? 0
            cclocation.stop()
            
            XCTAssert(finalMessagesCount <= initialMessagesCount)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.5)
    }
    
    // connection available
    func testRadioSilenceNot0() {
        let expectation = XCTestExpectation(description: "Data should be collected in database without being sent until radioSilence passes")
        
        let cclocation = CCLocation.sharedInstance
        cclocation.start(apiKey: testAPIKey)

        let colocatorManager = cclocation.colocatorManager
        let ccRequestMessages = colocatorManager?.ccRequestMessaging
     
        colocatorManager?.deleteDatabaseContent()
        
        let initialMessagesCount = ccRequestMessages?.getMessageCount() ?? 0
              
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ccRequestMessages?.stateStore.dispatch( TimeBetweenSendsTimerReceivedAction(timeInMilliseconds: 5000))
            
            cclocation.sendMarker(message: "Test marker 1")
            cclocation.sendMarker(message: "Test marker 2")
            cclocation.sendMarker(message: "Test marker 3")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let finalMessagesCount = ccRequestMessages?.getMessageCount() ?? 0
            cclocation.stop()
            
            XCTAssert(finalMessagesCount > initialMessagesCount)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 4.0)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
