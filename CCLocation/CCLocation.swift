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
import CoreLocation
import CoreMotion
import UserNotifications
import UIKit

internal struct Constants {
    static let kDefaultEndPointPartialUrl = ".colocator.net:443/socket"
    static let kEndPointUpdateLibraryBackgroundUrl = "https://canconnect.colocator.net/connect/connectping"
}

@objc public protocol CCLocationDelegate: class {
    @objc func ccLocationDidConnect()
    @objc func ccLocationDidFailWithError(error: Error)
    @objc func didReceiveCCLocation(_ location: LocationResponse)
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
    
    /// Start the Colocator library with credentials
    ///
    @objc public func start(apiKey: String, urlString: String? = nil) {
        if libraryStarted == false {
            libraryStarted = true
            
            setLoggerLevels(verbose: false, info: false, debug: false, warning: false, error: true, severe: true)
            
            NSLog("[Colocator] Initialising Colocator")
            
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
            NSLog("[Colocator] already running: Colocator start method called more than once in a row")
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
    
    @available(*, deprecated, message: "Replaced by addAlias(key, value) method")
    @objc public func setAliases(aliases: Dictionary<String, String>) {
        colocatorManager?.setAliases(aliases: aliases)
    }
    
    @objc public func addAlias(key: String, value: String) {
        colocatorManager?.addAlias(key: key, value: value)
    }
    
    @available(*, deprecated, message: "Replaced by triggerMotionPermissionPopUp() method")
    @objc public static func askMotionPermissions() {
        CCLocation.sharedInstance.triggerMotionPermissionPopUp()
    }
   
    @objc public func triggerMotionPermissionPopUp() {
        CMPedometer().stopUpdates()
        CCLocation.sharedInstance.colocatorManager?.ccInertial?.updateFitnessAndMotionStatus()
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
        
        Log.info("[Colocator] Updating library in background from \(wakeUpSource) - Checking client status for \(key.uppercased())")
        
        URLSession.shared.dataTask(with: request) { (data, response, err) in
            guard err == nil, let dataResponse = data else {
                completion(false)
                return
            }
            
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: dataResponse, options: []) as? [String: Any]
                let clientStatus = jsonResponse?["connect"] as? Bool
                
                if clientStatus == true {
                    if self.libraryStarted == true {
                        self.stop()
                        self.start(apiKey: key)
                        Log.info("[Colocator] Library started from background")
                        completion(true)
                        return
                    } else {
                        self.start(apiKey: key)
                        Log.info("[Colocator] Library started from background")
                        completion(true)
                        return
                    }
                }
                if clientStatus == false {
                    self.stop()
                    Log.info("[Colocator] Library stopped from background")
                    completion(false)
                    return
                }
                completion(false)
                
            } catch let parsingError {
                completion(false)
                Log.warning("[Colocator] Failed to get client's status in background. Error: \(parsingError)")
            }
        }.resume()
        
    }
    
    //MARK: - Location Callbacks
    
    @objc public func requestLocation() {
        if libraryStarted == true && colocatorManager?.ccRequestMessaging != nil {
            colocatorManager?.ccRequestMessaging?.sendLocationRequestMessage(type: 1)
            Log.info("[Colocator] Requested one Colocator location")
        } else {
            Log.error("[Colocator] Failed to request one Colocator location")
        }
    }
    
    @objc public func registerLocationListener() {
        if libraryStarted == true && colocatorManager?.ccRequestMessaging != nil {
            colocatorManager?.ccRequestMessaging?.sendLocationRequestMessage(type: 2)
            Log.info("[Colocator] Registered for Colocator location updates")
        } else {
            Log.error("[Colocator] Failed to register for Colocator location updates")
        }
    }
    
    @objc public func unregisterLocationListener() {
        if libraryStarted == true && colocatorManager?.ccRequestMessaging != nil {
            Log.info("[Colocator] Unregistered for Colocator location updates")
            colocatorManager?.ccRequestMessaging?.sendLocationRequestMessage(type: 3)
        } else {
            Log.error("[Colocator] Failed to unregister for Colocaor location updates")
        }
    }
    
    // MARK: - Test Library Integration
    
    @objc public func testLibraryIntegration() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        
        var locationPermission = "unidentified"
        var bluetoothPermission = "unidentified"
        var motionPermission = "unidentified"
        var notificationsPermission = "unidentified"
        
        if #available(iOS 13.1, *) {
            switch CBManager.authorization {
            case .notDetermined: bluetoothPermission = "Not Determined"
            case .restricted: bluetoothPermission = "Restricted"
            case .denied: bluetoothPermission = "Denied"
            case .allowedAlways: bluetoothPermission = "Allowed Always"
            }
        } else {
            // Fallback on earlier versions
            notificationsPermission = "unidentified      Reason: iOS < 13.1"
        }
        
        if #available(iOS 11.0, *) {
            switch CMPedometer.authorizationStatus() {
            case .notDetermined: motionPermission = "Not Determined"
            case .restricted: motionPermission = "Restricted"
            case .denied: motionPermission = "Denied"
            case .authorized: motionPermission = "Authorized"
            }
        } else {
            // Fallback on earlier versions
            notificationsPermission = "unidentified      Reason: iOS < 11.0"
        }
        
        if #available(iOS 10.0, *) {
            let currentNotification = UNUserNotificationCenter.current()
            currentNotification.getNotificationSettings(completionHandler: { (settings) in
                 if settings.authorizationStatus == .notDetermined {
                    notificationsPermission = "Not Determined"
                 } else if settings.authorizationStatus == .denied {
                    notificationsPermission = "Denied"
                 } else if settings.authorizationStatus == .authorized {
                    notificationsPermission = "Authorized"
                 }
                semaphore.signal()
              })
        } else {
            // Fallback on earlier versions
            notificationsPermission = "unidentified      Reason: iOS < 10.0"
        }
      
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined: locationPermission = "Not Determined"
        case .restricted: locationPermission = "Restricted"
        case .denied: locationPermission = "Denied"
        case .authorizedAlways: locationPermission = "Always"
        case .authorizedWhenInUse: locationPermission = "When In Use"
        }
        
        var deviceToken = "unidentified"
        var pushNotificationProvider = "unidentified"
        
        if let aliases = UserDefaults.standard.value(forKey: CCSocketConstants.kAliasKey) as? Dictionary<String, String> {
            for (key, value) in aliases {
                if key == "apns_user_id" {
                    deviceToken = value
                    pushNotificationProvider = "APNS"
                } else if key == "expo_token" {
                    deviceToken = value
                    pushNotificationProvider = "Expo"
                } else if key == "fcm_user_id" {
                    deviceToken = value
                    pushNotificationProvider = "Firebase"
                } else if key == "one_signal_token" {
                    deviceToken = value
                    pushNotificationProvider = "One Signal"
                } else if key == "pinpointEndpoint" {
                    deviceToken = value
                    pushNotificationProvider = "Pinpoint"
                } else if key == "pushwooshUserId" {
                    deviceToken = value
                    pushNotificationProvider = "Pushwhoosd"
                } else if key == "snsEndpoint" {
                    deviceToken = value
                    pushNotificationProvider = "APNSNSS"
                } else if key == "UAid" {
                    deviceToken = value
                    pushNotificationProvider = "Urban Airship"
                }
            }
        }
        
        // TODO - Add test for Silent Push Notification
        
        // Optional step - Check if the server has all the data required for a SPN
        // Call stop library
        // Request SPN from CC server through API
        // Get the average time for delivering the PN and add a margin of error
        // Wait for a while (see above step) and check if library status switched to on automatically
        // Add result in integrationTestResponse
        
        let silentPushNotificationResult = "unidentified"
        
        _ = semaphore.wait(timeout: .now() + 3)
        let integrationTestResponse = """
        
        
           ====  Integration Test Response  ====
        
        Device ID: \(getDeviceId() ?? "unidentified")
        Library Status: \(libraryStarted == true ? "On" : "Off")
        
        Location Permission Status: \(locationPermission)
        Bluetooth Permission Status: \(bluetoothPermission)
        Motion Permission Status: \(motionPermission)
        Notification Permission Status: \(notificationsPermission)
        
        Registered for Remote Notification: \(UIApplication.shared.isRegisteredForRemoteNotifications)
        Push Notification Provider: \(pushNotificationProvider)
        Notification Device Token: \(deviceToken)
        
           ====  Integration Test Response  ====
        
        """
        
        return integrationTestResponse
    }
}

//MARK: - CCSocketDelegate

extension CCLocation: CCSocketDelegate {
    func receivedLocationMessages(_ messages: [LocationResponse]) {
        Log.info("[Colocator] Received LocationResponse messages from Colocator\n\(messages)")
        for message in messages {
            delegate?.didReceiveCCLocation(message)
        }
    }
    
    func receivedTextMessage(message: NSDictionary) {
        Log.verbose("Received text message from Colocator\n\(message)")
    }
    
    func ccSocketDidConnect() {
        self.delegate?.ccLocationDidConnect()
        colocatorManager?.ccInertial?.updateFitnessAndMotionStatus()
    }
    
    func ccSocketDidFailWithError(error: Error) {
        self.delegate?.ccLocationDidFailWithError(error: error)
    }
}
