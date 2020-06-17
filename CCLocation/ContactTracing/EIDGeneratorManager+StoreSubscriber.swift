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
            if let secret = newEidState.secret {
                self.secret = secret
            }
            if let k = newEidState.k {
                self.k = Int(k)
            }
            if let clockOffset = newEidState.clockOffset {
                self.clockOffset = Int(clockOffset)
            }
            
            Log.debug("ContactTracing: New EID state is: \(newEidState)")
            
            if renewEIDTimer != nil {
                renewEIDTimer?.invalidate()
                renewEIDTimer = nil
            }
            
            currentEIDState = newEidState
        }
    }
}
