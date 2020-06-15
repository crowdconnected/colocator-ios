//
//  ContactTracing.swift
//  CCLocation
//
//  Created by TCode on 15/06/2020.
//  Copyright © 2020 Crowd Connected. All rights reserved.
//

import Foundation
import CoreBluetooth
import ReSwift

protocol CCContactTracingDelegate: class {
    func detectedContact(data: Data)
}

class ContactTracing: NSObject {
    private var advertisingInterval = 10000
    private var advertisingPeriod = 5000
    private var scanningInterval = 10000
    private var scanningPeriod = 5000
    
    private var advertiser: ContactAdvertiser?
    private var scanner: ContactScanner?
    
    private var queue = DispatchQueue(label: "ColocatorBroadcaster")
     
    let centralRestoreIdentifier: String = "ColocatorCentralRestoreIdentifier"
    let peripheralRestoreIdentifier: String = "ColocatorPeripheralRestoreIdentifier"
       
    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    
    var currentContactState: ContactBluetoothState!
    weak var stateStore: Store<LibraryState>!
    public weak var delegate: CCContactTracingDelegate?
    
    init(stateStore: Store<LibraryState>) {
        super.init()
        
        self.stateStore = stateStore
        currentContactState = ContactBluetoothState(isEnabled: false,
                                           serviceUUID: "",
                                           scanInterval: 0,
                                           scanDuration: 0,
                                           advertiseInterval: 0,
                                           advertiseDuration: 0)
        stateStore.subscribe(self)
    }
    
    //internal
    public func start() {
        startAdvertisingCycle()
        startScanningCycle()
    }
    
    public func stop() {
        peripheral?.stopAdvertising()
        central?.stopScan()
        advertiser = nil
        scanner = nil
    }
    
    private func startAdvertisingCycle() {
        advertiser = ContactAdvertiser()
        
        peripheral = CBPeripheralManager(delegate: advertiser,
                                         queue: queue,
                                         options: [CBPeripheralManagerOptionRestoreIdentifierKey: peripheralRestoreIdentifier])
    }
    
    private func startScanningCycle() {
        if advertiser == nil {
            print("Scanner cannot start while advertiser is nil")
            return
        }
        
        scanner = ContactScanner(advertiser: advertiser!, queue: queue)
        
        central = CBCentralManager(delegate: scanner,
                                          queue: queue,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(true),
                                                    CBCentralManagerOptionRestoreIdentifierKey: centralRestoreIdentifier,
                                                    CBCentralManagerOptionShowPowerAlertKey: NSNumber(false)])
    }
}
