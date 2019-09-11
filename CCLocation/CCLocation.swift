//
//  CCRequest.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 16/10/2016.
//  Copyright © 2016 Crowd Connected. All rights reserved.
//

import Foundation
import ReSwift
import CoreBluetooth
import CoreMotion

internal struct Constants {
    static let kDefaultEndPointPartialUrl = ".colocator.net:443/socket"
    static let kEndPointUpdateLibraryBackgroundUrl = "https://canconnect.colocator.net/connect/connectping"
}

@objc public protocol CCLocationDelegate: class {
    @objc func ccLocationDidConnect()
    @objc func ccLocationDidFailWithError(error: Error)
}

@objc public class CCLocation: NSObject {
    
    @objc public weak var delegate: CCLocationDelegate?
    
    var stateStore: Store<LibraryState>?
    var libraryStarted: Bool?
    var colocatorManager: ColocatorManager?
    
    @objc public static let sharedInstance : CCLocation = {
        let instance = CCLocation()
        instance.libraryStarted = false
        return instance
    }()
    
    @objc public static func askMotionPermissions () {
        CMPedometer().stopUpdates()
    }
    
    /// Start the Colocator library with credentials
    ///
    @objc public func start(apiKey: String, urlString: String? = nil) {
        if libraryStarted == false {
            libraryStarted = true
            
            Log.info("[Colocator] Initialising Colocator")
            
            var tempUrlString = apiKey + Constants.kDefaultEndPointPartialUrl
            
            if urlString != nil {
                tempUrlString = urlString!
            }
             
            stateStore = Store<LibraryState> (
                reducer: libraryReducer,
                state: nil
            )
            
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
    @objc public func stop() {
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
    @objc public func setLoggerLevels(verbose: Bool,
                                      info: Bool,
                                      debug: Bool,
                                      warning: Bool,
                                      error: Bool,
                                      severe: Bool) {
        Log.configureLoggerLevelsDisplayed(verbose: verbose,
                                           info: info,
                                           debug: debug,
                                           warning: warning,
                                           error: error,
                                           severe: severe)
    }
    
    @objc public func getDeviceId() -> String? {
        return CCSocket.sharedInstance.deviceId
    }
    
    @objc public func sendMarker(message: String) {
        colocatorManager?.sendMarker(data: message)
    }
    
    @available(*, deprecated, message: "Replaced by addAlias(key, value) method")
    @objc public func setAliases(aliases: Dictionary<String, String>) {
        colocatorManager?.setAliases(aliases: aliases)
    }
    
    @objc public func addAlias(key: String, value: String) {
        colocatorManager?.addAlias(key: key, value: value)
    }
    
    @objc public func triggerBluetoothPermissionPopUp() {
        var centralManager: CBCentralManager? = nil
        centralManager = CBCentralManager(delegate: nil,
                                          queue: nil,
                                          options: [CBCentralManagerOptionShowPowerAlertKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            centralManager?.delegate = nil
            centralManager = nil
        })
    }
    
    @objc public func receivedSilentNotification(userInfo: [AnyHashable : Any], clientKey key: String, completion: @escaping (Bool) -> Void) {
        updateLibraryBasedOnClientStatus(clientKey: key, isSilentNotification: true) { isNewData in
            completion(isNewData)
        }
    }
    
    @objc public func updateLibraryBasedOnClientStatus(clientKey key: String, isSilentNotification: Bool = false, completion: @escaping (Bool) -> Void) {
        let endpointUrlString = Constants.kEndPointUpdateLibraryBackgroundUrl
        let deviceID = getDeviceId() ?? ""
        let wakeUpSource = isSilentNotification ? "SPN" : "BR"
        
         var urlComponents = URLComponents(string: endpointUrlString)
        urlComponents?.queryItems = [URLQueryItem(name: "app", value: key),
                                     URLQueryItem(name: "deviceID", value: deviceID),
                                     URLQueryItem(name: "wakeUp", value: wakeUpSource)]
        
        guard let requestURL = urlComponents?.url  else {
            completion(false)
            return
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        Log.info("Updating library in background from \(wakeUpSource) - Checking client status for \(key.uppercased())")
        
        URLSession.shared.dataTask(with: request) { (data, response, err) in
            guard err == nil, let dataResponse = data else {
                completion(false)
                return
            }
            
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: dataResponse, options: []) as? [String: Any]
                let clientStatus = jsonResponse?["connect"] as? Bool
                
                if clientStatus == true {
                    self.start(apiKey: key)
                    Log.info("Library started from background")
                    completion(true)
                    return
                }
                if clientStatus == false {
                    self.stop()
                    Log.info("Library stopped from background")
                    completion(false)
                    return
                }
                completion(false)
                
            } catch let parsingError {
                completion(false)
                Log.warning("Failed to get client's status in background. Error: \(parsingError)")
            }
        }.resume()
        
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
