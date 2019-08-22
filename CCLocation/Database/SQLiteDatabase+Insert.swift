//
//  SQLiteDatabase+Inserts.swift
//  CCLocation
//
//  Created by Mobile Developer on 22/08/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import Foundation
import SQLite3

// Extension Insert

extension SQLiteDatabase {
    
    // MARK: - Beacons
    
    func insertBeacon(beacon: Beacon) throws {
        ibeaconBeaconBuffer.append(beacon)
    }
    
    func insertBundlediBeacons() throws {
        try serialiBeaconDatabaseQueue.sync {
            guard ibeaconBeaconBuffer.count > 0 else {
                return
            }
            
            let total_count = try count(table: CCLocationTables.IBEACON_MESSAGES_TABLE)
            
            try saveResetAutoincrement(table: CCLocationTables.IBEACON_MESSAGES_TABLE)
            
            Log.info("Flushing iBeacon buffer with \(ibeaconBeaconBuffer.count)")
            
            guard sqlite3_exec(dbPointer, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else  {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            let insertSql = "INSERT INTO \(CCLocationTables.IBEACON_MESSAGES_TABLE) (UUID, MAJOR, MINOR, PROXIMITY, ACCURACY, RSSI, TIMEINTERVAL) VALUES (?, ?, ?, ?, ?, ?, ?);"
            let insertStatement = try prepareStatement(sql: insertSql)
            
            for beacon in ibeaconBeaconBuffer {
                let uuid: NSString = beacon.uuid
                let major: Int32 = beacon.major
                let minor: Int32 = beacon.minor
                let proximity: Int32 = beacon.proximity
                let accuracy: Double = beacon.accuracy
                let rssi: Int32 = beacon.rssi
                let timeInterval: Double = beacon.timeIntervalSinceBootTime
                
                guard sqlite3_bind_text(insertStatement, 1, uuid.utf8String, -1, nil) == SQLITE_OK &&
                    sqlite3_bind_int(insertStatement, 2, major) == SQLITE_OK &&
                    sqlite3_bind_int(insertStatement, 3, minor) == SQLITE_OK &&
                    sqlite3_bind_int(insertStatement, 4, proximity) == SQLITE_OK &&
                    sqlite3_bind_double(insertStatement, 5, accuracy) == SQLITE_OK &&
                    sqlite3_bind_int(insertStatement, 6, rssi) == SQLITE_OK &&
                    sqlite3_bind_double(insertStatement, 7, timeInterval) == SQLITE_OK else {
                        throw SQLiteError.Bind(message: errorMessage)
                }
                
                guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                    throw SQLiteError.Step(message: errorMessage)
                }
                guard sqlite3_reset(insertStatement) == SQLITE_OK else {
                    throw SQLiteError.Step(message: errorMessage)
                }
            }
            
            if total_count >= CCLocationConstants.MAX_QUEUE_SIZE {
                
                let deleteDiff = total_count - CCLocationConstants.MAX_QUEUE_SIZE
                
                sqlite3_clear_bindings(insertStatement)
                sqlite3_reset(insertStatement)
                
                let deleteSql = "DELETE FROM \(CCLocationTables.IBEACON_MESSAGES_TABLE) WHERE ID IN (SELECT ID FROM \(CCLocationTables.IBEACON_MESSAGES_TABLE) ORDER BY ID LIMIT \(deleteDiff));"
                
                Log.debug("DB: \(deleteSql)")
                
                let deleteStatement = try prepareStatement(sql: deleteSql)
                
                guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                    NSLog("Failed to delete message record from database");
                    throw SQLiteError.Step(message: errorMessage)
                }
            }
            
            guard sqlite3_finalize(insertStatement) == SQLITE_OK else {
                throw SQLiteError.Finalise(message: errorMessage)
            }
            
            guard sqlite3_exec(dbPointer, "COMMIT TRANSACTION", nil, nil, nil) == SQLITE_OK else {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            ibeaconBeaconBuffer.removeAll()
        }
    }
    
    // MARK: - EddyStone Beacons
    
    func insertEddystoneBeacon(eddystoneBeacon: EddystoneBeacon) throws {
        eddystoneBeaconBuffer.append(eddystoneBeacon)
    }
    
    func insertBundledEddystoneBeacons() throws {
        try serialEddystoneDatabaseQueue.sync {
            guard eddystoneBeaconBuffer.count > 0 else {
                return
            }
            
            let total_count = try count(table: CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE)
            
            Log.info("Flushing eddystone beacon buffer with \(eddystoneBeaconBuffer.count)")
            
            try saveResetAutoincrement(table: CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE)
            
            guard sqlite3_exec(dbPointer, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else  {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            let insertSql = "INSERT INTO \(CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE) (EID, TX, RSSI, TIMEINTERVAL) VALUES (?, ?, ?, ?);"
            let insertStatement = try prepareStatement(sql: insertSql)
            
            for eddystoneBeacon in eddystoneBeaconBuffer {
                let eid: NSString = eddystoneBeacon.eid
                let rssi: Int32 = eddystoneBeacon.rssi
                let tx: Int32 = eddystoneBeacon.tx
                let timeInterval: Double = eddystoneBeacon.timeIntervalSinceBootTime
                
                guard sqlite3_bind_text(insertStatement, 1, eid.utf8String, -1, nil) == SQLITE_OK &&
                    sqlite3_bind_int(insertStatement, 2, tx) == SQLITE_OK &&
                    sqlite3_bind_int(insertStatement, 3, rssi) == SQLITE_OK &&
                    sqlite3_bind_double(insertStatement, 4, timeInterval) == SQLITE_OK else {
                        throw SQLiteError.Bind(message: errorMessage)
                }
                
                guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                    throw SQLiteError.Step(message: errorMessage)
                }
                guard sqlite3_reset(insertStatement) == SQLITE_OK else {
                    throw SQLiteError.Step(message: errorMessage)
                }
            }
            
            if total_count >= CCLocationConstants.MAX_QUEUE_SIZE {
                let deleteDiff = total_count - CCLocationConstants.MAX_QUEUE_SIZE
                
                sqlite3_clear_bindings(insertStatement)
                sqlite3_reset(insertStatement)
                
                let deleteSql = "DELETE FROM \(CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE) WHERE ID IN (SELECT ID FROM \(CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE) ORDER BY ID LIMIT \(deleteDiff));"
                
                Log.debug("DB: \(deleteSql)")
                
                let deleteStatement = try prepareStatement(sql: deleteSql)
                
                guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                    NSLog("Failed to delete message record from database");
                    throw SQLiteError.Step(message: errorMessage)
                }
            }
            
            guard sqlite3_finalize(insertStatement) == SQLITE_OK else {
                throw SQLiteError.Finalise(message: errorMessage)
            }
            
            guard sqlite3_exec(dbPointer, "COMMIT TRANSACTION", nil, nil, nil) == SQLITE_OK else {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            eddystoneBeaconBuffer.removeAll()
        }
    }
    
    // MARK: - Messages
    
    func insertMessage(ccMessage: CCMessage) throws {
        messagesBuffer.append(ccMessage)
        Log.verbose("DB: insertMessage: \(ccMessage.observation.count) \(ccMessage.observation.hexEncodedString())")
    }
    
    func insertBundledMessages() throws {
        try serialMessageDatabaseQueue.sync {
            guard messagesBuffer.count > 0 else {
                return
            }
            
            let total_count = try count(table: CCLocationTables.MESSAGES_TABLE)
            
            try saveResetAutoincrement(table: CCLocationTables.MESSAGES_TABLE)
            
            guard sqlite3_exec(dbPointer, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else  {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            let insertSql = "INSERT INTO \(CCLocationTables.MESSAGES_TABLE) (OBSERVATION) VALUES (?);"
            let insertStatement = try prepareStatement(sql: insertSql)
            
            for message in messagesBuffer {
                let data = message.observation

                let observationBase64 = data.base64EncodedString() as NSString
                
                guard sqlite3_bind_text(insertStatement, 1, observationBase64.utf8String, -1, nil) == SQLITE_OK else {
                    throw SQLiteError.Bind(message: errorMessage)
                }
                    
                guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                    throw SQLiteError.Step(message: errorMessage)
                }
                guard sqlite3_reset(insertStatement) == SQLITE_OK else {
                    throw SQLiteError.Step(message: errorMessage)
                }
            }
            
            if total_count >= CCLocationConstants.MAX_QUEUE_SIZE {
                
                let deleteDiff = total_count - CCLocationConstants.MAX_QUEUE_SIZE
                
                sqlite3_clear_bindings(insertStatement)
                sqlite3_reset(insertStatement)
                
                let deleteSql = "DELETE FROM \(CCLocationTables.MESSAGES_TABLE) WHERE ID IN (SELECT ID FROM \(CCLocationTables.MESSAGES_TABLE) ORDER BY ID LIMIT \(deleteDiff));"
                
                Log.debug("DB: \(deleteSql)")
                
                let deleteStatement = try prepareStatement(sql: deleteSql)
                
                guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                    NSLog("Failed to delete message record from database");
                    throw SQLiteError.Step(message: errorMessage)
                }
            }
            
            guard sqlite3_finalize(insertStatement) == SQLITE_OK else {
                throw SQLiteError.Finalise(message: errorMessage)
            }
            
            guard sqlite3_exec(dbPointer, "COMMIT TRANSACTION", nil, nil, nil) == SQLITE_OK else {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            messagesBuffer.removeAll()
        }
    }
}
