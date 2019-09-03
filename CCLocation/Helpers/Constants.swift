//
//  Constants.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 06/03/2017.
//  Copyright © 2017 Crowd Connected. All rights reserved.
//

import Foundation

struct CCLocationTables {
    static let IBEACON_MESSAGES_TABLE = "IBEACONMESSAGES"
    static let EDDYSTONE_BEACON_MESSAGES_TABLE = "EDDYSTONEBEACONMESSAGES"
    static let MESSAGES_TABLE = "MESSAGES"
}

struct CCLocationMessageType {
    static let SYSTEM_SETTINGS = "SYSTEM_SETTINGS"
}

struct CCLocationConstants {
    static let MAX_QUEUE_SIZE = 100000
}

struct CCSocketConstants {
    static let LIBRARY_VERSION_TO_REPORT = "2.2.1"
    static let LAST_DEVICE_ID_KEY = "LastDeviceId"
    static let MIN_DELAY: Double = 1 * 1000
    static let MAX_DELAY: Double = 60 * 60 * 1000
    static let MAX_CYCLE_DELAY: Double = 24 * 60 * 60 * 1000
    static let WS_PREFIX = "wss://"
    static let ALIAS_KEY = "Aliases"
}

struct CCRequestMessagingConstants {
    static let messageCounter = "messageCounterKey"
    static let kNotAvaialble = "Not Available"
}

struct CCInertialConstants {
    static let bufferSize = 500 // do not make smaller than 50
    static let cutOff = 100
}
