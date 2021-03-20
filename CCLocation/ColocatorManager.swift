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
    var ccContactTracing: ContactTracing?
    var ccEidGenerator: EIDGeneratorManager?
    var ccSocket: CCSocket?
    
    var messagesDatabase: SQLiteDatabase!
    var beaconsDatabase: SQLiteDatabase!
    var eddystoneBeaconsDatabase:  SQLiteDatabase!
    
    // Separate databases for different usage
    private let messagesDBName = "observations.db"                      // Storing the messages before being sent to the server
    private let iBeaconMessagesDBName = "iBeaconMessages.db"            // Storing the monitored beacons
    private let eddystoneBeaconMessagesDBName = "eddystoneMessages.db"  // Storing the monitored eddystone
    
    // When stopping the library, the main components and refences are removed
    // After a second, all the data in the database starts being sent to the server
    // The transfer process should be completed in less than 120 seconds, before the connection will be closed
    var stopLibraryTimer: Timer?
    var secondsFromStopTrigger = 0
    
    public static let sharedInstance: ColocatorManager = {
        let instance = ColocatorManager()
        instance.openLocalDatabase()
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
            deviceId = UserDefaults.standard.string(forKey: CCSocketConstants.kLastDeviceIDKey)
           
            ccServerURLString = urlString
            ccAPIKeyString = apiKey
            state = stateStore
        
            ccSocket = CCSocket.sharedInstance
            ccSocket!.delegate = ccLocation

            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    return
                }
                
                self.ccLocationManager = CCLocationManager(stateStore: stateStore)
                self.ccLocationManager!.delegate = self
            }

            ccInertial = CCInertial(stateStore: stateStore)
            ccInertial!.delegate = self

            ccEidGenerator = EIDGeneratorManager(stateStore: stateStore)
            ccContactTracing = ContactTracing(stateStore: stateStore)
            ccContactTracing?.eidGenerator = ccEidGenerator
            ccContactTracing?.delegate = self
            
            ccRequestMessaging = CCRequestMessaging(ccSocket: ccSocket!, stateStore: stateStore)
            
            Log.info("[Colocator] Attempt to connect to back-end with URL: \(urlString) and APIKey: \(apiKey)")
                       
            ccSocket?.start(urlString: urlString,
                            apiKey: apiKey,
                            ccRequestMessaging: ccRequestMessaging!)
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
            
            ccInertial?.stop()
            ccInertial?.delegate = nil
            ccInertial = nil
            
            ccContactTracing?.stop()
            ccContactTracing?.delegate = nil
            ccContactTracing = nil
            
            Log.info("[Colocator] Sending all messages from local database to server before stopping")
        
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
        
        // Destroy connection if the data transfer takes more than 120 seconds
        if secondsFromStopTrigger > ColocatorManagerConstants.kMaxTimeSendingDataAtStop {
            let leftMessages = ccRequestMessaging?.getMessageCount() ?? 0
            Log.warning("[Colocator] Library stopped. \(leftMessages) unsent messages")
            
            destroyConnection()
            secondsFromStopTrigger = 0
            return
        }
        
        // Destroy connection immediately if the database is empty
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
    
    // Stop location observations and collection geo data
    // Method used if there was no network connection for the last 24 hours since the library started
    // Prevent data overriding in the databse and collecting data that won't be sent to the server
    public func stopLocationObservations() {
        ccLocationManager?.stopAllLocationObservations()
        ccLocationManager?.updateGEOAndBeaconStatesWithoutObservations()
    }
    
    // Store the pairs in UserDefaults and send them to the server
    public func setAliases(aliases: Dictionary<String, String>) {
        UserDefaults.standard.set(aliases, forKey: CCSocketConstants.kAliasKey)
        if let ccRequestMessaging = self.ccRequestMessaging {
            ccRequestMessaging.processAliases(aliases: aliases)
        }
    }
    
    // Store the pair in UserDefaults and send it to the server
    public func addAlias(key: String, value: String) {
        let alias = [key: value]
        updateAliasesInUserDefaults(alias)
        if let ccRequestMessaging = self.ccRequestMessaging {
            ccRequestMessaging.processAliases(aliases: alias)
        }
    }
    
    private func updateAliasesInUserDefaults(_ alias: Dictionary<String, String>) {
        let defaults = UserDefaults.standard
        
        var newAliasesDictionary: Dictionary<String, String> = [:]
        if let oldAliases = defaults.value(forKey: CCSocketConstants.kAliasKey) as? Dictionary<String, String> {
            newAliasesDictionary = oldAliases
        }
        for (key, value) in alias {
            newAliasesDictionary.updateValue(value, forKey: key)
        }
        defaults.setValue(newAliasesDictionary, forKey: CCSocketConstants.kAliasKey)
    }
    
    func deleteDatabaseContent() {
        Log.warning("[Colocator] Attempt to delete all the content inside the database")
        
        do {
            try messagesDatabase.deleteMessages(messagesTable: CCLocationTables.kMessagesTable)
        } catch {
            Log.error("[Colocator] Failed to delete messages content in database.")
        }
        
        do {
            try   beaconsDatabase.deleteBeacons(beaconTable: CCLocationTables.kIBeaconMessagesTable)
        } catch {
            Log.error("[Colocator] Failed to delete beacons content in database.")
        }

        do {
            try eddystoneBeaconsDatabase.deleteBeacons(beaconTable: CCLocationTables.kEddystoneBeaconMessagesTable)
        } catch {
            Log.error("[Colocator] Failed to delete eddystonebeacons content in database.")
        }
    }
    
    // It is important to close the databases once the library stops
    // Elsewise there will be multiple connections to the same databses when the library starts again
    // Leading to memory leaking
    deinit {
        if messagesDatabase != nil {
            messagesDatabase.close()
        }
        if beaconsDatabase != nil {
            beaconsDatabase.close()
        }
        if eddystoneBeaconsDatabase != nil {
            eddystoneBeaconsDatabase.close()
        }
    }
}

//MARK: - Database
extension ColocatorManager {
    
    func openLocalDatabase() {
        // Get the library directory
        let dirPaths = NSSearchPathForDirectoriesInDomains (.libraryDirectory, .userDomainMask, true)
        let docsDir = dirPaths[0]
        
        // Build the path to the database messages file
        let messageDBPath = URL.init(string: docsDir)?.appendingPathComponent(messagesDBName).absoluteString
        guard let messagesDBPathStringUnwrapped = messageDBPath else {
            Log.error("[Colocator] Unable to create messages database path")
            return
        }
        
        // Open messages database connection
        do {
            messagesDatabase = try SQLiteDatabase.open(path: messagesDBPathStringUnwrapped)
            Log.debug("Successfully opened connection to messages database.")
        } catch SQLiteError.OpenDatabase(let message) {
            Log.error("[Colocator] Unable to open observation messages database. \(message)")
        } catch {
            Log.error("[Colocator] An unexpected error was thrown, when trying to open a connection to observation messages database")
        }
        
        // Build the path to the database beacons file
        let beaconsDBPath = URL.init(string: docsDir)?.appendingPathComponent(iBeaconMessagesDBName).absoluteString
        guard let beaconsDBPathStringUnwrapped = beaconsDBPath else {
            Log.error("[Colocator] Unable to create messages database path")
            return
        }
        
        // Open beacons database connection
        do {
            beaconsDatabase = try SQLiteDatabase.open(path: beaconsDBPathStringUnwrapped)
            Log.debug("Successfully opened connection to beacons database.")
        } catch SQLiteError.OpenDatabase(let message) {
            Log.error("[Colocator] Unable to open observation beacons database. \(message)")
        } catch {
            Log.error("[Colocator] An unexpected error was thrown, when trying to open a connection to observation beacons database")
        }
        
        // Build the path to the database eddystone beacons file
        let eddystoneBeaconsDBPath = URL.init(string: docsDir)?.appendingPathComponent(eddystoneBeaconMessagesDBName).absoluteString
        guard let eddystoneBeaconsDBPathStringUnwrapped = eddystoneBeaconsDBPath else {
            Log.error("[Colocator] Unable to create eddystone beacons database path")
            return
        }
        
        // Open eddystone database connection
        do {
            eddystoneBeaconsDatabase = try SQLiteDatabase.open(path: eddystoneBeaconsDBPathStringUnwrapped)
            Log.debug("Successfully opened connection to eddystone beacons database.")
        } catch SQLiteError.OpenDatabase(let message) {
            Log.error("[Colocator] Unable to open observation eddystone beacons database. \(message)")
        } catch {
            Log.error("[Colocator] An unexpected error was thrown, when trying to open a connection to eddystone beacons database")
        }
    }
}

// MARK: - Device, Network, Library details
extension ColocatorManager {
    
    // Return a string containing the main details about the current device (model, OS, version)
    func deviceDescription() -> String {
        let deviceModel = self.platformString()
        let deviceOs = "iOS"
        let deviceVersion = UIDevice.current.systemVersion
        
        return String(format: "model=%@&os=%@&version=%@", deviceModel, deviceOs, deviceVersion)
    }
    
    // Return a string specifying whether there is a WiFi connection or a mobile connection
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
    
    // Return the Colocator library version used
    func libraryVersion() -> String {
        let libraryVersion = CCSocketConstants.kLibraryVersionToReport
        return String(format: "&libVersion=%@" , libraryVersion)
    }
    
    // Return the device model
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

// Handle all the events that must be reported to the server or that will change the library behaviour
extension ColocatorManager: CCLocationManagerDelegate {
    public func receivedGeofenceEvent(type: Int, region: CLCircularRegion) {
        ccRequestMessaging?.processGeofenceEvent(type: type, region: region)
    }
    
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

// MARK: - CCContactTracingDelegate
extension ColocatorManager: ContactScannerDelegate {
    func newContact(EID: String, RSSI: Int, timestamp: Double) {
        ccRequestMessaging?.processContact(EID: EID, RSSI: RSSI, timestamp: timestamp)
    }
}
