//
//  CCInertial.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 06/06/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import Foundation
import CoreMotion
import ReSwift

class CCInertial {
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    
    fileprivate var inertialState: InertialState!
    
    fileprivate weak var stateStore: Store<LibraryState>!

    public init(stateStore: Store<LibraryState>) {
        self.stateStore = stateStore
        
        inertialState = InertialState(isEnabled: false, interval: 0)
    }
}


