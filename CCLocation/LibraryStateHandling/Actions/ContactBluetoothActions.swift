//
//  ContactActions.swift
//  CCLocation
//
//  Created by TCode on 15/06/2020.
//  Copyright © 2020 Crowd Connected. All rights reserved.
//

import ReSwift

struct ContactBluetoothStateChangedAction: Action {
    var isEnabled: Bool?
    var serviceUUID: String?
    var scanInterval: UInt32?
    var scanDuration: UInt32?
    var advertiseInterval: UInt32?
    var advertiseDuration: UInt32?
}

struct DisableContactBluetoothAction: Action {}
