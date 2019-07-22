//
//  CCRequest.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 16/10/2016.
//  Copyright © 2016 Crowd Connected. All rights reserved.
//

import Foundation
import ReSwift
import CoreMotion

internal struct Constants {
    static let DEFAULT_END_POINT_PARTIAL_URL = ".colocator.net:443/socket"
}

public protocol CCLocationDelegate: class {
    func ccLocationDidConnect()
    func ccLocationDidFailWithError(error: Error)
}

public class CCLocation:NSObject {
    
    public weak var delegate: CCLocationDelegate?
    
    var stateStore: Store<LibraryState>?
    var libraryStarted: Bool?
    var colocatorManager: ColocatorManager?
    
    public static let sharedInstance : CCLocation = {
        let instance = CCLocation()
        instance.libraryStarted = false
        return instance
    }()
    
    public static func askMotionPermissions () {
        CMPedometer().stopUpdates()
    }
    
    /// Start the Colocator library with credentials
    ///
    public func start (apiKey: String, urlString: String? = nil) {
        if libraryStarted == false {
            libraryStarted = true
            
            Log.info("[Colocator] Initialising Colocator")
            
            var tempUrlString = apiKey + Constants.DEFAULT_END_POINT_PARTIAL_URL
            
            if urlString != nil {
                tempUrlString = urlString!
            }
             
            stateStore = Store<LibraryState> (
                reducer: libraryReducer,
                state: nil
            )
            
            Log.info("[Colocator] Attempt to connect to back-end with URL: \(tempUrlString) and APIKey: \(apiKey)")
            
            colocatorManager = ColocatorManager.sharedInstance
            colocatorManager?.start(urlString: tempUrlString,
                                    apiKey: apiKey,
                                    ccLocation: self,
                                    stateStore: stateStore!)
        } else {
            Log.info("[Colocator] already running: Colocator start method called more than once in a row")
        }
    }
    
    /// Stop the Colocator library
    ///
    public func stop (){
        if libraryStarted == true {
            libraryStarted = false
            stateStore = nil
            
            colocatorManager?.stop()
            colocatorManager = nil
        } else {
            NSLog("[Colocator] already stopped")
        }
    }
    
    /// Filter the log levels that appears in the console
    ///
    public func setLoggerLevels(verbose: Bool,
                                info: Bool,
                                debug: Bool,
                                warninig: Bool,
                                error: Bool,
                                severe: Bool) {
        Log.configureLoggerLevelsDisplayed(verbose: verbose,
                                           info: info,
                                           debug: debug,
                                           warninig: warninig,
                                           error: error,
                                           severe: severe)
    }
    
    public func getDeviceId() -> String? {
        return CCSocket.sharedInstance.deviceId
    }
    
    public func sendMarker(message: String) {
        colocatorManager?.sendMarker(data: message)
    }
    
    public func setAliases(aliases:Dictionary<String, String>) {
        colocatorManager?.setAliases(aliases: aliases)
    }
}

extension CCLocation: CCSocketDelegate {
    func receivedTextMessage(message: NSDictionary) {
        Log.verbose("Received text message from socket")
    }
    
    func ccSocketDidConnect() {
        self.delegate?.ccLocationDidConnect()
    }
    
    func ccSocketDidFailWithError(error: Error) {
        self.delegate?.ccLocationDidFailWithError(error: error)
    }
}
