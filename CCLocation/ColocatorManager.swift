//
//  ColocatorManager.swift
//  CCLocation
//
//  Created by Mobile Developer on 12/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import CoreLocation
import Foundation
import ReSwift

class ColocatorManager {
    
    private(set)var deviceId: String?
    var running: Bool = false
    var startTime: Date?
    
    var ccServerURLString: String?
    var ccAPIKeyString: String?
    
    var state: Store<LibraryState>?
    var ccLocationManager: CCLocationManager?
    var ccRequestMessaging: CCRequestMessaging?
    var ccInertial: CCInertial?
    var ccSocket: CCSocket?
    
    var stopLibraryTimer: Timer?
    var secondsFromStopTrigger = 0
    
    public static let sharedInstance: ColocatorManager = {
        let instance = ColocatorManager()
        return instance
    }()
    
    func start(urlString: String,
               apiKey: String,
               ccLocation: CCLocation,
               stateStore: Store<LibraryState>) {
        if !running {
            
            running = true
            
            if stopLibraryTimer != nil {
                destroyConnection()
            }
            stopLibraryTimer?.invalidate()
            stopLibraryTimer = nil
            
            startTime = Date()
            deviceId = UserDefaults.standard.string(forKey: CCSocketConstants.LAST_DEVICE_ID_KEY)
           
            ccServerURLString = urlString
            ccAPIKeyString = apiKey
            state = stateStore
        
            ccSocket = CCSocket.sharedInstance
            ccSocket!.delegate = ccLocation
            
            ccLocationManager = CCLocationManager(stateStore: state!)
            ccInertial = CCInertial(stateStore: state!)
            ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket!,
                                                    stateStore: state!)
            
            ccLocationManager!.delegate = self
            ccInertial!.delegate = self
            
            Log.info("[Colocator] Attempt to connect to back-end with URL: \(urlString) and APIKey: \(apiKey)")
                       
            ccSocket?.start(urlString: urlString,
                            apiKey: apiKey,
                            ccRequestMessaging: ccRequestMessaging!)
            
            Log.debug("[Colocator] Started Colocator Framework")
        } else {
            stop()
            start(urlString: urlString,
                  apiKey: apiKey,
                  ccLocation: ccLocation,
                  stateStore: stateStore)
        }
    }
    
    public func stop() {
        // Helps for debugging of possible retain cycles to ensure library shuts down correctly
        Log.debug("CCRequest retain cycle count: \(CFGetRetainCount(ccSocket))")
        Log.debug("CCLocationManager retain cycle count: \(CFGetRetainCount(ccLocationManager))")
        Log.debug("CCRequestMessaging retain cycle count: \(CFGetRetainCount(ccRequestMessaging))")

        if running {
            running = false
            
            ccLocationManager?.stop()
            ccLocationManager?.delegate = nil
            ccLocationManager = nil
            
            Log.info("Sending all messages from local database to server before stopping")
        
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.ccRequestMessaging?.sendQueuedMessagesAndStopTimer()
            }
        
            stopLibraryTimer = Timer.scheduledTimer(timeInterval: 1.0,
                                                    target: self,
                                                    selector: #selector(checkDatabaseAndStopLibrary),
                                                    userInfo: nil,
                                                    repeats: true)
        }
    }
    
    @objc private func checkDatabaseAndStopLibrary() {
        secondsFromStopTrigger += 1
        
        if secondsFromStopTrigger > 60 {
            let leftMessages = ccRequestMessaging?.getMessageCount() ?? 0
            Log.warning("Library stopped. \(leftMessages) unsent messages")
            
            destroyConnection()
            secondsFromStopTrigger = 0
            return
        }
        
        if checkDatabaseEmptiness() {
            destroyConnection()
        }
    }
    
    private func checkDatabaseEmptiness() -> Bool {
        if let messagesLeft = ccRequestMessaging?.getMessageCount() {
            return messagesLeft == 0
        }
        return true
    }
    
    private func destroyConnection() {
        stopLibraryTimer?.invalidate()
        stopLibraryTimer = nil
        
        ccRequestMessaging?.stop()
        ccRequestMessaging = nil
        
        ccSocket?.stop()
        ccSocket?.delegate = nil
        ccSocket = nil
        
        Log.info("[Colocator] Active back-end connection destroyed")
    }
    
    public func stopLocationObservations() {
        ccLocationManager?.stopAllLocationObservations()
    }
    
    public func setAliases(aliases: Dictionary<String, String>) {
        UserDefaults.standard.set(aliases, forKey: CCSocketConstants.ALIAS_KEY)
        if let ccRequestMessaging = self.ccRequestMessaging {
            ccRequestMessaging.processAliases(aliases: aliases)
        }
    }
    
    public func sendMarker(data: String) {
        if let ccRequestMessaging = self.ccRequestMessaging {
            ccRequestMessaging.processMarker(data: data)
        }
    }
}

// MARK: - Device, Network, Library details
extension ColocatorManager {
    func deviceDescription() -> String {
        let deviceModel = self.platformString()
        let deviceOs = "iOS"
        let deviceVersion = UIDevice.current.systemVersion
        
        return String(format: "model=%@&os=%@&version=%@", deviceModel, deviceOs, deviceVersion)
    }
    
    func networkType() -> String {
        var networkType: String = ""
        if ReachabilityManager.shared.isReachableViaWiFi() {
            networkType = "&networkType=WIFI"
        }
        if ReachabilityManager.shared.isReachableViaWan() {
            networkType = "&networkType=MOBILE"
        }
        
        return networkType
    }
    
    func libraryVersion() -> String {
        let libraryVersion = CCSocketConstants.LIBRARY_VERSION_TO_REPORT
        return String(format: "&libVersion=%@" , libraryVersion)
    }
    
    func platform() -> NSString {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0,  count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        
        return String(cString: machine) as NSString
    }
    
    func platformString() -> String {
        let platform = self.platform()
        guard let devicePlatform = DevicePlatform(rawValue: String(platform)) else {
            return platform as String
        }
        
        return devicePlatform.title
    }
}

// MARK: - CCLocationManagerDelegate
extension ColocatorManager: CCLocationManagerDelegate {
    public func receivedEddystoneBeaconInfo(eid: NSString, tx: Int, rssi: Int, timestamp: TimeInterval) {
        let tempString = String(eid).hexa2Bytes
        ccRequestMessaging?.processEddystoneEvent(eid: NSData(bytes: tempString, length: tempString.count) as Data,
                                                  tx: tx,
                                                  rssi: rssi,
                                                  timestamp: timestamp)
    }
    
    public func receivedGEOLocation(location: CLLocation) {
        ccRequestMessaging?.processLocationEvent(location: location)
    }
    
    public func receivediBeaconInfo(proximityUUID: UUID,
                                    major: Int,
                                    minor: Int,
                                    proximity: Int,
                                    accuracy: Double,
                                    rssi: Int,
                                    timestamp: TimeInterval) {
        ccRequestMessaging?.processIBeaconEvent(uuid: proximityUUID,
                                                major: major,
                                                minor: minor,
                                                rssi: rssi,
                                                accuracy: accuracy,
                                                proximity: proximity,
                                                timestamp: timestamp)
    }
}

// MARK: - CCInertialDelegate
extension ColocatorManager: CCInertialDelegate {
    func receivedStep(date: Date, angle: Double) {
        ccRequestMessaging?.processStep(date: date, angle: angle)
    }
}
