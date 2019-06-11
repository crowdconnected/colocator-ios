//
//  CCRequest.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 16/10/2016.
//  Copyright © 2016 Crowd Connected. All rights reserved.
//

import Foundation
import ReSwift

internal struct Constants {
    static let DEFAULT_END_POINT_PARTIAL_URL = ".colocator.net:443/socket"
}

public protocol CCLocationDelegate: class {
    func ccLocationDidConnect()
    func ccLocationDidFailWithError(error: Error)
}

public class CCLocation:NSObject {
    
    public weak var delegate: CCLocationDelegate?
    
    var stateStore:Store<LibraryState>?

    var ccRequestObject: CCSocket?
    var ccRequestMessaging: CCRequestMessaging?
    var ccLocationManager: CCLocationManager?
    var ccInertial: CCInertial?
    var libraryStarted: Bool?
    
    public static let sharedInstance : CCLocation = {
        let instance = CCLocation()
        instance.libraryStarted = false
        return instance
    } ()
    
    public func start (apiKey: String, urlString: String? = nil) {
        
        if libraryStarted == false {
            
            libraryStarted = true
            
            NSLog ("[Colocator] Initialising Colocator")
            
            var tempUrlString = apiKey + Constants.DEFAULT_END_POINT_PARTIAL_URL
            
            if urlString != nil {
                tempUrlString = urlString!
            }
             
            stateStore = Store<LibraryState> (
                reducer: libraryReducer,
                state: nil
            )
            
            ccRequestObject = CCSocket.sharedInstance
            ccRequestMessaging = CCRequestMessaging(ccSocket: ccRequestObject!, stateStore: stateStore!)
            ccLocationManager = CCLocationManager(stateStore: stateStore!)
            ccInertial = CCInertial(stateStore: stateStore!)
            
            ccRequestObject!.delegate = self

            NSLog ("[Colocator] Attempt to connect to back-end with URL: \(tempUrlString) and APIKey: \(apiKey)")
            
            ccRequestObject!.start(urlString: tempUrlString, apiKey: apiKey, ccRequestMessaging: ccRequestMessaging!, ccLocationManager: ccLocationManager!)
        } else {
            NSLog ("[Colocator] already running: Colocator start method called more than once in a row")
        }
    }
    
    public func getDeviceId () -> String? {
        return ccRequestObject?.deviceId
    }
    
    public func sendMarker (message: String){
        ccRequestObject?.sendMarker(data: message)
    }
    
    public func setAliases (aliases:Dictionary<String, String>) {
        ccRequestObject?.setAliases(aliases: aliases)
    }
    
    public func stop (){
        // help for debugging of possible retain cycles to ensure library shuts down correctly
        // add as needed below
//        print("CCRequest retain cycle count: \(CFGetRetainCount(ccRequestObject))")
//        print("CCLocationManager retain cycle count: \(CFGetRetainCount(ccLocationManager))")
//        print("CCRequestMessaging retain cycle count: \(CFGetRetainCount(ccRequestMessaging))")

        if libraryStarted == true {
            libraryStarted = false
            ccLocationManager?.stop()
            ccLocationManager?.delegate = nil

            ccRequestObject!.stop()
            ccRequestObject!.delegate = nil
            
            ccInertial?.stop()

            ccRequestMessaging?.stop()

            stateStore = nil
            ccLocationManager = nil
            ccRequestObject = nil
            ccRequestMessaging = nil
            ccInertial = nil
        } else {
            NSLog("[Colocator] already stopped")
        }
    }
}

extension CCLocation: CCSocketDelegate {
    func receivedTextMessage(message: NSDictionary) {
    }
    
    func ccSocketDidConnect() {
        self.delegate?.ccLocationDidConnect()

    }
    
    func ccSocketDidFailWithError(error: Error) {
        self.delegate?.ccLocationDidFailWithError(error: error)
    }
}
