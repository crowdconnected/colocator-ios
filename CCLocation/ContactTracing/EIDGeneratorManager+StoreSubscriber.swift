//
//  EIDGeneratorManager+StoreSubscriber.swift
//  CCLocation
//
//  Created by TCode on 15/06/2020.
//  Copyright © 2020 Crowd Connected. All rights reserved.
//

import Foundation
import ReSwift

extension EIDGeneratorManager: StoreSubscriber {
    
    public func newState(state: LibraryState) {
        guard let newEidState = state.contactState?.eidState else {
            return
        }
        
        if newEidState != currentEIDState {
            //TODO Upload secret, k and clockoffset
            
            Log.debug("ContactTracing: New EID state is: \(newEidState)")
            
            updateCurrentEIDStateActivity(newState: newEidState)
            currentEIDState = newEidState
        }
    }
    
    private func updateCurrentEIDStateActivity(newState: ContactBluetoothState) {
        //TODO Update behaviour depending on the settings
    }
}
