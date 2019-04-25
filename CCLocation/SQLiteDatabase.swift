//
//  SQLiteDatabase.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 08/03/2018.
//  Copyright © 2018 Crowd Connected. All rights reserved.
//

import Foundation
import SQLite3

enum SQLiteError: Error {
    case OpenDatabase(message: String)
    case Prepare(message: String)
    case Step(message: String)
    case Bind(message: String)
    case Exec(message: String)
    case Finalise(message: String)
}

struct Beacon {
    let uuid: NSString
    let major: Int32
    let minor: Int32
    let proximity: Int32
    let accuracy: Double
    let rssi: Int32
    let timeIntervalSinceBootTime: Double
}

struct EddystoneBeacon {
    let eid: NSString
    let rssi: Int32
    let tx: Int32
    let timeIntervalSinceBootTime: Double
}

struct CCMessage {
    let observation: Data
}

protocol SQLTable {
    static var createStatement: String { get }
}

class SQLiteDatabase {
    
    var messagesBuffer : [CCMessage] = [CCMessage] ()
    var eddystoneBeaconBuffer : [EddystoneBeacon] = [EddystoneBeacon] ()
    var ibeaconBeaconBuffer : [Beacon] = [Beacon] ()
    weak var messagesBufferClearTimer : Timer?
    let serialMessageDatabaseQueue = DispatchQueue(label: "com.crowdConnected.serielMessageDatabaseQueue")
    let serialiBeaconDatabaseQueue = DispatchQueue(label: "com.crowdConnected.serieliBeaconDatabaseQueue")
    let serialEddystoneDatabaseQueue = DispatchQueue(label: "com.crowdConnected.EddystoneDatabaseQueue")
    
    fileprivate let dbPointer: OpaquePointer?
    
    var errorMessage: String {
        if let errorPointer = sqlite3_errmsg(dbPointer) {
            let errorMessage = String(cString: errorPointer)
            return errorMessage
        } else {
            return "No error message provided from sqlite."
        }
    }
    
    fileprivate init(dbPointer: OpaquePointer?) {
        self.dbPointer = dbPointer
        messagesBufferClearTimer = Timer.scheduledTimer(timeInterval: TimeInterval(1), target: self, selector: #selector(clearBuffers), userInfo: nil, repeats: true)
    }
    
    func close () {
        if messagesBufferClearTimer != nil {
            messagesBufferClearTimer?.invalidate()
            messagesBufferClearTimer = nil
        }
        sqlite3_close(dbPointer)
    }
    
    deinit {
        if messagesBufferClearTimer != nil {
            messagesBufferClearTimer?.invalidate()
            messagesBufferClearTimer = nil
        }
        sqlite3_close(dbPointer)
    }
    
    static func open(path: String) throws -> SQLiteDatabase {
        var db: OpaquePointer? = nil
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK {
            return SQLiteDatabase(dbPointer: db)
        } else {
            defer {
                if db != nil {
                    sqlite3_close(db)
                }
            }
            
            if let errorPointer = sqlite3_errmsg(db) {
                let message = String.init(cString: errorPointer)
                throw SQLiteError.OpenDatabase(message: message)
            } else {
                throw SQLiteError.OpenDatabase(message: "No error message provided from sqlite.")
            }
        }
    }
    
    @objc func clearBuffers() throws {
        try insertBundlediBeacons()
        try insertBundledMessages()
        try insertBundledEddystoneBeacons()
    }
}

extension SQLiteDatabase {
    func prepareStatement(sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer? = nil
        guard sqlite3_prepare_v2(dbPointer, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.Prepare(message: errorMessage)
        }
        
        return statement
    }
}

extension SQLiteDatabase {
    func createTable(table: SQLTable.Type) throws {
        let createTableStatement = try prepareStatement(sql: table.createStatement)
        
        defer {
            sqlite3_finalize(createTableStatement)
        }
        
        guard sqlite3_step(createTableStatement) == SQLITE_DONE else {
            throw SQLiteError.Step(message: errorMessage)
        }
    }
}

extension SQLiteDatabase {
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
            
            Log.verbose("Flushing iBeacon buffer with \(ibeaconBeaconBuffer.count)")
            
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
            
            if (total_count >= CCLocationConstants.MAX_QUEUE_SIZE) {
                
                let deleteDiff = total_count - CCLocationConstants.MAX_QUEUE_SIZE
                
                sqlite3_clear_bindings(insertStatement)
                sqlite3_reset(insertStatement)
                
                let deleteSql = "DELETE FROM \(CCLocationTables.IBEACON_MESSAGES_TABLE) WHERE ID IN (SELECT ID FROM \(CCLocationTables.IBEACON_MESSAGES_TABLE) ORDER BY ID LIMIT \(deleteDiff));"
                Log.debug("\(deleteSql)")
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
}

extension SQLiteDatabase {
    func insertEddystoneBeacon(eddystoneBeacon: EddystoneBeacon) throws {
        eddystoneBeaconBuffer.append(eddystoneBeacon)
    }
    
    @objc func insertBundledEddystoneBeacons() throws {
        
        try serialEddystoneDatabaseQueue.sync {
            
            guard eddystoneBeaconBuffer.count > 0 else {
                return
            }
            
            let total_count = try count(table: CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE)
            
            Log.verbose("Flushing eddystone beacon buffer with \(eddystoneBeaconBuffer.count)")
            
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
            
            if (total_count >= CCLocationConstants.MAX_QUEUE_SIZE) {
                
                let deleteDiff = total_count - CCLocationConstants.MAX_QUEUE_SIZE
                
                sqlite3_clear_bindings(insertStatement)
                sqlite3_reset(insertStatement)
                
                let deleteSql = "DELETE FROM \(CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE) WHERE ID IN (SELECT ID FROM \(CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE) ORDER BY ID LIMIT \(deleteDiff));"
                Log.debug("\(deleteSql)")
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
}

extension SQLiteDatabase {
    func insertMessage(ccMessage: CCMessage) throws {
        messagesBuffer.append(ccMessage)
//        Log.debug("insertMessage: \(ccMessage.observation.count) \(ccMessage.observation.hexEncodedString())")
    }
    
    @objc func insertBundledMessages() throws {
        
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
            
            if (total_count >= CCLocationConstants.MAX_QUEUE_SIZE) {
                
                let deleteDiff = total_count - CCLocationConstants.MAX_QUEUE_SIZE
                
                sqlite3_clear_bindings(insertStatement)
                sqlite3_reset(insertStatement)
                
                let deleteSql = "DELETE FROM \(CCLocationTables.MESSAGES_TABLE) WHERE ID IN (SELECT ID FROM \(CCLocationTables.MESSAGES_TABLE) ORDER BY ID LIMIT \(deleteDiff));"
                Log.debug("\(deleteSql)")
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

extension SQLiteDatabase {
    func popMessages(num: Int) throws -> [Data]  {
        
        let data = try serialMessageDatabaseQueue.sync { () -> [Data] in
            
            var clientMessageData: Data
            var clientMessagesData: [Data] = [Data] ()
            var ids : [String] = [String] ()
            
            guard sqlite3_exec(dbPointer, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else  {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            let sql = "SELECT * FROM \(CCLocationTables.MESSAGES_TABLE) ORDER BY ID ASC LIMIT \(num);"
            let statement = try prepareStatement(sql: sql)
            
            while sqlite3_step(statement) == SQLITE_ROW {

                let observationBase64 = sqlite3_column_text(statement, 1)
                
                let string = String(cString: observationBase64!)
                
                clientMessageData = Data(base64Encoded: string)!
                clientMessagesData.append(clientMessageData)

                let id = sqlite3_column_int(statement, 0)
                ids.append("\(id)")
            }
            
            sqlite3_reset(statement)
            
            if (clientMessagesData.count > 0) {
                let idsJoined = ids.joined(separator: ",")
                let deleteSql = "DELETE FROM \(CCLocationTables.MESSAGES_TABLE) WHERE ID IN (\(idsJoined));"
                let statement = try prepareStatement(sql: deleteSql)
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SQLiteError.Step(message: errorMessage)
                }
            }
            else {
                throw SQLiteError.Step(message: errorMessage)
            }
            
            guard sqlite3_finalize(statement) == SQLITE_OK else {
                throw SQLiteError.Finalise(message: errorMessage)
            }
            
            guard sqlite3_exec(dbPointer, "COMMIT TRANSACTION", nil, nil, nil) == SQLITE_OK else {
                throw SQLiteError.Exec(message: errorMessage)
            }
            
            return clientMessagesData
        }
        
        return data
    }
}

extension SQLiteDatabase {
    func allBeaconsAndDelete() throws -> [Beacon]? {
        
        let resultBeacons = try serialiBeaconDatabaseQueue.sync { () -> [Beacon]? in
            
            var beacons:[Beacon]?
            
            do {
                beacons = try allBeacons()
            } catch SQLiteError.Prepare(let message) {
                throw SQLiteError.Prepare(message: message)
            }
            
            do {
                try deleteBeacons(beaconTable: CCLocationTables.IBEACON_MESSAGES_TABLE)
            } catch SQLiteError.Prepare(let message) {
                throw SQLiteError.Prepare(message: message)
            }
            
            return beacons
        }
        return resultBeacons
    }
}

extension SQLiteDatabase {
    func allEddystoneBeaconsAndDelete() throws -> [EddystoneBeacon]? {
        
        let resultBeacons = try serialEddystoneDatabaseQueue.sync { () -> [EddystoneBeacon]? in
            
            var beacons:[EddystoneBeacon]?
            
            do {
                beacons = try allEddystoneBeacons()
            } catch SQLiteError.Prepare(let message) {
                throw SQLiteError.Prepare(message: message)
            }
            
            do {
                try deleteBeacons(beaconTable: CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE)
            } catch SQLiteError.Prepare(let message) {
                throw SQLiteError.Prepare(message: message)
            }
            
            return beacons
        }
        
        return resultBeacons
    }
}



extension SQLiteDatabase {
    func deleteBeacons(beaconTable: String) throws {
        
        let deleteMessagesSQL = "DELETE FROM \(beaconTable);"
        
        guard let deleteMessagesStatement = try? prepareStatement(sql: deleteMessagesSQL) else {
            throw SQLiteError.Prepare(message: errorMessage)
        }
        
        defer {
            sqlite3_finalize(deleteMessagesStatement)
        }
        
        guard sqlite3_step(deleteMessagesStatement) == SQLITE_DONE else {
            throw SQLiteError.Step(message: errorMessage)
        }
        
        try saveResetAutoincrement(table: beaconTable)
    }
}

extension SQLiteDatabase {
    func saveResetAutoincrement(table:String) throws {
        
        if try count(table: table) == 0 {
            
            let resetAutoincrementSql = "DELETE FROM sqlite_sequence WHERE name = '\(table)';"
            
            guard let resetAutoincrementStatement = try? prepareStatement(sql: resetAutoincrementSql) else {
                throw SQLiteError.Prepare(message: errorMessage)
            }
            
            defer {
                sqlite3_finalize(resetAutoincrementStatement)
            }
            
            guard sqlite3_step(resetAutoincrementStatement) == SQLITE_DONE else {
                throw SQLiteError.Step(message: errorMessage)
            }
        }
    }
}

extension SQLiteDatabase {
    fileprivate func allBeacons() throws -> [Beacon]? {
        let querySql = "SELECT * FROM \(CCLocationTables.IBEACON_MESSAGES_TABLE) ORDER BY ID ASC;"
        var beacons:[Beacon]?
        
        guard let queryStatement = try? prepareStatement(sql: querySql) else {
            throw SQLiteError.Prepare(message: errorMessage)
        }
        
        defer {
            sqlite3_finalize(queryStatement)
        }
        
        while sqlite3_step(queryStatement) == SQLITE_ROW {
            let uuid = sqlite3_column_text(queryStatement, 1)
            let major = sqlite3_column_int(queryStatement, 2)
            let minor = sqlite3_column_int(queryStatement, 3)
            let proxomity = sqlite3_column_int(queryStatement, 4)
            let accuracy = sqlite3_column_double(queryStatement, 5)
            let rssi = sqlite3_column_int(queryStatement, 6)
            let timeInterval = sqlite3_column_double(queryStatement, 7)
            
            let beacon = Beacon(uuid: String(cString: uuid!) as NSString, major: major, minor: minor, proximity: proxomity, accuracy: accuracy, rssi: rssi, timeIntervalSinceBootTime: timeInterval)
            
            if beacons == nil {
                beacons = []
            }
            
            beacons!.append(beacon)
        }
        
        return beacons
    }
}

extension SQLiteDatabase {
    fileprivate func allEddystoneBeacons() throws -> [EddystoneBeacon]? {
    
        let querySql = "SELECT * FROM \(CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE) ORDER BY ID ASC;"
        var beacons:[EddystoneBeacon]?
        
        guard let queryStatement = try? prepareStatement(sql: querySql) else {
            throw SQLiteError.Prepare(message: errorMessage)
        }
        
        defer {
            sqlite3_finalize(queryStatement)
        }
        
        while sqlite3_step(queryStatement) == SQLITE_ROW {
            let eid = sqlite3_column_text(queryStatement, 1)
            let tx = sqlite3_column_int(queryStatement, 2)
            let rssi = sqlite3_column_int(queryStatement, 3)
            let timeInterval = sqlite3_column_double(queryStatement, 4)
            
            let beacon = EddystoneBeacon(eid: String(cString: eid!) as NSString, rssi: rssi, tx: tx, timeIntervalSinceBootTime: timeInterval)
            
            if beacons == nil {
                beacons = []
            }
            
            beacons!.append(beacon)
        }
        
        return beacons
    }
}

extension SQLiteDatabase {
    func count(table:String) throws -> Int {
        
        var count: Int = -1
        
        let querySql = "SELECT COUNT(*) FROM " + table + ";"
        
        guard let queryStatement = try? prepareStatement(sql: querySql) else {
            throw SQLiteError.Prepare(message: errorMessage)
        }
        
        while(sqlite3_step(queryStatement) == SQLITE_ROW)
        {
            count = Int(sqlite3_column_int(queryStatement, 0));
        }
        
        defer {
            sqlite3_finalize(queryStatement)
        }
        
        //        if (count == 0){
        //            if try saveResetAutoincrement(table: table) {
        //                Log.debug("Successfully reset auto increment counter")
        //            }
        //        }
        
        return count
    }
}

extension Beacon : SQLTable {
    static var createStatement: String {
        return """
        CREATE TABLE IF NOT EXISTS \(CCLocationTables.IBEACON_MESSAGES_TABLE) (
        ID INTEGER PRIMARY KEY AUTOINCREMENT,
        UUID TEXT,
        MAJOR INTEGER,
        MINOR INTEGER,
        PROXIMITY INTEGER,
        ACCURACY REAL,
        RSSI INTEGER,
        TIMEINTERVAL REAL
        );
        """
    }
}

extension EddystoneBeacon : SQLTable {
    static var createStatement: String {
        return """
        CREATE TABLE IF NOT EXISTS \(CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE) (
        ID INTEGER PRIMARY KEY AUTOINCREMENT,
        EID TEXT,
        TX INTEGER,
        RSSI INTEGER,
        TIMEINTERVAL REAL
        );
        """
    }
}

extension CCMessage : SQLTable {
    static var createStatement: String {
        return """
        CREATE TABLE IF NOT EXISTS \(CCLocationTables.MESSAGES_TABLE) (
        ID INTEGER PRIMARY KEY AUTOINCREMENT,
        OBSERVATION BLOB
        );
        """
    }
}
