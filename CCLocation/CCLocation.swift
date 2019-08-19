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
            
            var tempUrlString = apiKey + Constants.DEFAULT_END_POINT_PARTIAL_URL
            
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
    
    @objc public func getDeviceId() -> String? {
        return CCSocket.sharedInstance.deviceId
    }
    
    @objc public func sendMarker(message: String) {
        colocatorManager?.sendMarker(data: message)
    }
    
    @objc public func setAliases(aliases:Dictionary<String, String>) {
        colocatorManager?.setAliases(aliases: aliases)
    }
    
    @objc public func handleBackgroundRefresh(clientKey key: String, completion: @escaping (Bool) -> Void) {
        let endpointUrlString = "https://en23kessvxam43o.m.pipedream.net"
        var urlComponents = URLComponents(string: endpointUrlString)
        urlComponents?.queryItems = [URLQueryItem(name: "clientKey", value: key)]
        
        guard let requestURL = urlComponents?.url  else {
            completion(false)
            return
        }
        let request = URLRequest(url: requestURL)
        
        Log.info("Background Refresh Event detected - Checking client status for \(key.uppercased()) ...")
        URLSession.shared.dataTask(with: request) { (data, response, err) in
            guard err == nil, let dataResponse = data else {
                completion(false)
                return
            }
            
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: dataResponse, options: []) as? [String: Any]
                let clientStatus = jsonResponse?["clientStatus"] as? Bool
                
                if clientStatus == true {
                    self.start(apiKey: key)
                    completion(true)
                } else {
                    completion(false)
                }
            } catch let parsingError {
                completion(false)
                print("Error", parsingError)
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
