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
    internal var isRunning = false
    
    internal var advertisingInterval = 10000
    internal var advertisingPeriod = 5000
    internal var scanningInterval = 10000
    internal var scanningPeriod = 5000
    
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
    public var eidGenerator: EIDGeneratorManager?
    
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
    
    internal func start() {
        print("Start contact tracing")
        //TODO Verify if it is better to initialize the EID here or at init. Check if it's actualizing his data before being used
        
        startAdvertisingCycle()
        startScanningCycle()
        
        //TODO Implement duration and interval for scanning and advertising
    }
    
    internal func stop() {
         print("Stop contact tracing")
        
        isRunning = false
        
        peripheral?.stopAdvertising()
        central?.stopScan()
        advertiser = nil
        scanner = nil
    }
    
    private func startAdvertisingCycle() {
        guard let eidGenerator = eidGenerator else {
            Log.warning("Cannot start advertising with a nil EIDGenerator")
            isRunning = false
            return
        }
        
        advertiser = ContactAdvertiser(eidGenerator: eidGenerator)
        
        peripheral = CBPeripheralManager(delegate: advertiser,
                                         queue: queue,
                                         options: [CBPeripheralManagerOptionRestoreIdentifierKey: peripheralRestoreIdentifier])
        isRunning = true
    }
    
    private func startScanningCycle() {
        if advertiser == nil {
            print("Scanner cannot start while advertiser is nil")
            return
        }
        
        scanner = ContactScanner(advertiser: advertiser!, queue: queue, delegate: self)
        
        central = CBCentralManager(delegate: scanner,
                                          queue: queue,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(true),
                                                    CBCentralManagerOptionRestoreIdentifierKey: centralRestoreIdentifier,
                                                    CBCentralManagerOptionShowPowerAlertKey: NSNumber(false)])
    }
}

extension ContactTracing: ContactScannerDelegate {
    func newContact(EID: String, RSSI: Int, timestamp: Double) {
        //TODO Convert this in Data or a specific ContactMessage
        
        let d = "".data(using: .utf8)!
        delegate?.detectedContact(data: d)
    }
}
