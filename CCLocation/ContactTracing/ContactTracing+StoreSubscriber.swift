//
//  ContactTracing+StoreSubscriber.swift
//  CCLocation
//
//  Created by TCode on 15/06/2020.
//  Copyright © 2020 Crowd Connected. All rights reserved.
//

import Foundation
import CoreBluetooth
import ReSwift

extension ContactTracing: StoreSubscriber {
    
    public func newState(state: LibraryState) {
        guard let newContactState = state.contactState?.contactBluetoothState else {
            return
        }
        
        if newContactState != currentContactState {
            if let serviceUUID = newContactState.serviceUUID {
                ContactTracingUUIDs.colocatorServiceUUID = CBUUID(string: serviceUUID)
            }
            if let scanInterval = newContactState.scanInterval {
                 //TODO Updatea all settings
            }
            if let scanDuration = newContactState.scanDuration {
                 //TODO Updatea all settings
            }
            if let advertiseInterval = newContactState.advertiseInterval {
                 //TODO Updatea all settings
            }
            if let advertiseDuration = newContactState.advertiseDuration {
                 //TODO Updatea all settings
            }
            
            Log.debug("ContactTracing: New state is: \(newContactState)")
            
            updateCurrentContactStateActivity(newState: newContactState)
            currentContactState = newContactState
        }
    }
    
    private func updateCurrentContactStateActivity(newState: ContactBluetoothState) {
        //TODO Update behaviour depending on the settings
        // reinitialize EIDManger
        //Delete and reinitialize advertsier and scanner
    }
}
