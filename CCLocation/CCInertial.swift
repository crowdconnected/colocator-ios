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

class CCInertial: NSObject {
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    
    fileprivate var currentInertialState: InertialState!
    
    weak var stateStore: Store<LibraryState>!

    init(stateStore: Store<LibraryState>) {
        super.init()
        
        self.stateStore = stateStore
        
        currentInertialState = InertialState(isEnabled: false, interval: 0)
        
        stateStore.subscribe(self)
    }
    
    internal func startCountingSteps() {
        pedometer.startUpdates(from: Date()) {
            [weak self] pedometerData, error in
            guard let pedometerData = pedometerData, error == nil else { return }
            
            DispatchQueue.main.async {
                print(String(describing: pedometerData.numberOfSteps))
                let receivedTime = String(NSDate().timeIntervalSince1970) + ","
                let start = String(pedometerData.startDate.timeIntervalSince1970 * 1000) + ","
                let end = String(pedometerData.endDate.timeIntervalSince1970 * 1000) + ","
                let numberOfSteps = pedometerData.numberOfSteps.stringValue + ","
                let distance = (pedometerData.distance?.stringValue ?? "N/A") + ","
                let currentPace = (pedometerData.currentPace?.stringValue ?? "N/A") + ","
                let currentCadence = (pedometerData.currentCadence?.stringValue ?? "N/A") + ","
                let floorsAscended = (pedometerData.floorsAscended?.stringValue ?? "N/A") + ","
                let floorsDescended = (pedometerData.floorsDescended?.stringValue ?? "N/A") + "\n"
                let dataStringPart1 = start  + end + receivedTime + numberOfSteps + distance
                let dataStringPart2 = currentPace + currentCadence + floorsAscended + floorsDescended
                
                let dataString = dataStringPart1 + dataStringPart2
                print(dataString)
            }
        }
    }
    

    internal func start () {
        Log.debug("Starting intertial")
        startCountingSteps()
    }
    
    internal func stop () {
        Log.debug("Stopping inertial")
        pedometer.stopUpdates()
    }
}

// MARK:- StoreSubscriber delegate
extension CCInertial: StoreSubscriber {
    public func newState(state: LibraryState) {
        if let newInertialState = state.intertialState {

            Log.debug("new state is: \(newInertialState)")
            
            if newInertialState != self.currentInertialState {
                self.currentInertialState = newInertialState
                Log.debug("new state is: \(newInertialState)")
                
                if let isInertialEnabled = newInertialState.isEnabled {
                    if isInertialEnabled {
                        start()
                    } else {
                        stop()
                    }
                }
            }
        }
    }
}
