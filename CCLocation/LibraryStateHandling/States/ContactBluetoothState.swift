//
//  ContactState.swift
//  CCLocation
//
//  Created by TCode on 15/06/2020.
//  Copyright © 2020 Crowd Connected. All rights reserved.
//

import ReSwift

public struct ContactBluetoothState: StateType, AutoEquatable {
    var isEnabled: Bool?
    var serviceUUID: String?
    var scanInterval: UInt32?
    var scanDuration: UInt32?
    var advertiseInterval: UInt32?
    var advertiseDuration: UInt32?
    
    init(isEnabled: Bool?,
         serviceUUID: String?,
         scanInterval: UInt32?,
         scanDuration: UInt32?,
         advertiseInterval: UInt32?,
         advertiseDuration: UInt32?) {
        
        self.isEnabled = isEnabled
        self.serviceUUID = serviceUUID
        self.scanInterval = scanInterval
        self.scanDuration = scanDuration
        self.advertiseInterval = advertiseInterval
        self.advertiseDuration = advertiseDuration
    }
}
