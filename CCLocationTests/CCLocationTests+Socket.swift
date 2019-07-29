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
        let apiKey = "123456"
        let state = Store<LibraryState> (
            reducer: libraryReducer,
            state: nil
        )
        let ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket,
                                                    stateStore: state)
        
        ccSocket.start(urlString: urlString,
                       apiKey: apiKey,
                       ccRequestMessaging: ccRequestMessaging)
        
        let createdURL = ccSocket.webSocket?.url.absoluteString.contains(urlString)
        XCTAssert(createdURL == true)
    }
    
    func testUnsuccessfullConnectionToSocket() {
        let ccSocket = CCSocket()
        let urlString = "staging.colocator.net:443/wrongURLString"
        let apiKey = "123456"
        let state = Store<LibraryState> (
            reducer: libraryReducer,
            state: nil
        )
        let ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket,
                                                    stateStore: state)
        
        ccSocket.start(urlString: urlString,
                       apiKey: apiKey,
                       ccRequestMessaging: ccRequestMessaging)
        
        let createdURL = ccSocket.webSocket?.url.absoluteString.contains(urlString)
        XCTAssert(createdURL == false)
    }
    
    func testUnableToConnectFor24h() {
        let ccSocket = CCSocket()
        let urlString = "staging.colocator.net:443/wrongURLString"
        let apiKey = "123456"
        let state = Store<LibraryState> (
            reducer: libraryReducer,
            state: nil
        )
        let ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket,
                                                    stateStore: state)
        
        ccSocket.start(urlString: urlString,
                       apiKey: apiKey,
                       ccRequestMessaging: ccRequestMessaging)
        
        ccSocket.stopCycler()
        
        //check database to be empty
        //check collectiondata to stop
        
    }
}
