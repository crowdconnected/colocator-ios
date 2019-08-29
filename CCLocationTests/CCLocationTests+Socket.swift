//
//  CCLocationTests+Socket.swift
//  CCLocationTests
//
//  Created by Mobile Developer on 26/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import XCTest
import CoreLocation
import ReSwift
@testable import CCLocation

extension CCLocationTests {
    
    func testSuccessfullConnectionToSocket() {
        let ccSocket = CCSocket()
        let urlString = "staging.colocator.net:443/socket"
        let state = Store<LibraryState> (
            reducer: libraryReducer,
            state: nil
        )
        let ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket,
                                                    stateStore: state)
        ccSocket.start(urlString: urlString,
                       apiKey: testAPIKey,
                       ccRequestMessaging: ccRequestMessaging)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            XCTAssert(ccSocket.delay == CCSocketConstants.MIN_DELAY)
        }
    }
    
    func testSuccessfullConnectionToSocketWithoutURL() {
        let cclocation = CCLocation()
        cclocation.start(apiKey: testAPIKey)
        
        let ccSocket = cclocation.colocatorManager?.ccRequestMessaging?.ccSocket
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            XCTAssert(ccSocket?.delay == CCSocketConstants.MIN_DELAY)
        }
    }
    
    func testUnsuccessfullConnectionToSocket() {
        let ccSocket = CCSocket()
        let urlString = "staging.colocator.net:443/wrongURLString"
        let state = Store<LibraryState> (
            reducer: libraryReducer,
            state: nil
        )
        let ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket,
                                                    stateStore: state)
        
        ccSocket.start(urlString: urlString,
                       apiKey: testAPIKey,
                       ccRequestMessaging: ccRequestMessaging)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            XCTAssert(ccSocket.delay > CCSocketConstants.MIN_DELAY)
        }
    }
    
    func testPresenceOfAllDeviceData() {
        let ccSocket = CCSocket()
        let urlString = "staging.colocator.net:443/socket"
        let state = Store<LibraryState> (
            reducer: libraryReducer,
            state: nil
        )
        let ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket,
                                                    stateStore: state)
        ccSocket.start(urlString: urlString,
                       apiKey: testAPIKey,
                       ccRequestMessaging: ccRequestMessaging)
        let finalURL = ccSocket.createWebsocketURL(url: ccSocket.ccWebsocketBaseURL ?? "", id: ccSocket.deviceId)
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            var allInfoIsPresent = false
            
            if let absoluteString = finalURL?.absoluteString {
                allInfoIsPresent = absoluteString.contains("model") &&
                    absoluteString.contains("os") &&
                    absoluteString.contains("version") &&
                    absoluteString.contains("modnetworkTypeel") &&
                    absoluteString.contains("libVersion")
            }
            
            XCTAssert(allInfoIsPresent)
        }
    }
}
