//
//  CCLocationManager+DatabaseOperations.swift
//  CCLocation
//
//  Created by Mobile Developer on 04/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import CoreLocation
import Foundation

// Extension Database Operations

extension CCLocationManager {
    
    public func countBeacons() {
        
        do {
            let beaconCount = try iBeaconMessagesDB.count(table:CCLocationTables.IBEACON_MESSAGES_TABLE)
            Log.debug("Process beacon table, beacon count: \(String(describing: beaconCount))")
        } catch {
            Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
        }
    }
    
    public func countEddystoneBeacons() {
        
        do {
            let beaconCount = try eddystoneBeaconMessagesDB.count(table:CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE)
            Log.debug("Process Eddystone beacon table, beacon count: \(String(describing: beaconCount))")
        } catch {
            Log.debug("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
        }
    }
    
    public func getAllBeaconsAndDelete() -> [Beacon]? {
        
        var beacons: [Beacon]?
        
        do {
            try beacons = iBeaconMessagesDB.getAllBeaconsAndDelete()
        } catch {
            Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
        }
        
        return beacons
    }
    
    public func getAllEddystoneBeaconsAndDelete() -> [EddystoneBeacon]? {
        
        var beacons: [EddystoneBeacon]?
        
        do {
            try beacons = eddystoneBeaconMessagesDB.getAllEddystoneBeaconsAndDelete()
            
        } catch {
            Log.error("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
        }
        
        return beacons
    }
    
    // MARK:- iBeacon database handling
    
    func openIBeaconDatabase() {
        
        // Get the library directory
        let dirPaths = NSSearchPathForDirectoriesInDomains (.libraryDirectory, .userDomainMask, true)
        
        let docsDir = dirPaths[0]
        
        // Build the path to the database file
        let beaconDBPath = URL.init(string: docsDir)?.appendingPathComponent(iBeaconMessagesDBName).absoluteString
        
        guard let beaconDBPathStringUnwrapped = beaconDBPath else {
            Log.error("Unable to create beacon database path")
            return
        }
        
        do {
            iBeaconMessagesDB = try SQLiteDatabase.open(path: beaconDBPathStringUnwrapped)
            Log.debug("Successfully opened connection to beacon database.")
        } catch SQLiteError.OpenDatabase(let message) {
            Log.error("Unable to open database. \(message)")
        } catch {
            Log.error("An unexpected error was thrown, when trying to open a connection to beacon database")
        }
    }
    
    public func createIBeaconTable() {
        
        do {
            try iBeaconMessagesDB.createTable(table: Beacon.self)
        } catch {
            Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
        }
    }
    
    func insert(beacon: CLBeacon) {
        
        if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
            
            do {
                try iBeaconMessagesDB.insertBeacon(beacon: Beacon (
                    uuid: beacon.proximityUUID.uuidString as NSString,
                    major: beacon.major.int32Value,
                    minor: beacon.minor.int32Value,
                    proximity: Int32(beacon.proximity.rawValue),
                    accuracy: beacon.accuracy,
                    rssi: Int32(beacon.rssi),
                    timeIntervalSinceBootTime: timeIntervalSinceBoot
                ))
            } catch {
                Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
            }
        }
    }
    
    // MARK:- Eddystone Beacon database handling
    
    func openEddystoneBeaconDatabase() {
        
        // Get the library directory
        let dirPaths = NSSearchPathForDirectoriesInDomains (.libraryDirectory, .userDomainMask, true)
        
        let docsDir = dirPaths[0]
        
        // Build the path to the database file
        let beaconDBPath = URL.init(string: docsDir)?.appendingPathComponent(eddystoneBeaconMessagesDBName).absoluteString
        
        guard let beaconDBPathStringUnwrapped = beaconDBPath else {
            Log.error("Unable to create beacon database path")
            return
        }
        
        do {
            eddystoneBeaconMessagesDB = try SQLiteDatabase.open(path: beaconDBPathStringUnwrapped)
            Log.debug("Successfully opened connection to Eddystone database.")
        } catch SQLiteError.OpenDatabase(let message) {
            Log.error("Unable to open database. \(message)")
        } catch {
            Log.error("An unexpected error was thrown, when trying to open a connection to Eddystone database")
        }
    }
    
    func createEddystoneBeaconTable() {
        
        do {
            try eddystoneBeaconMessagesDB.createTable(table: EddystoneBeacon.self)
        } catch {
            Log.error("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
        }
    }
    
    func insert(eddystoneBeacon: EddystoneBeaconInfo) {
        
        if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
            
            do {
                try eddystoneBeaconMessagesDB.insertEddystoneBeacon(eddystoneBeacon: EddystoneBeacon (
                    eid: eddystoneBeacon.beaconID.hexBeaconID() as NSString,
                    rssi: Int32(eddystoneBeacon.RSSI),
                    tx: Int32(eddystoneBeacon.txPower),
                    timeIntervalSinceBootTime: timeIntervalSinceBoot
                ))
            } catch {
                Log.error("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
            }
        }
    }
}
