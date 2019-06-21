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

struct PedometerData {
    let endDate: Date
    let numberOfSteps: Int
}

struct YawData {
    let yaw: Double
    let date: Date
}

protocol CCInertialDelegate: class {
    func receivedStep(date: Date, angle: Double)
}

class CCInertial: NSObject {
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    
    private var pedometerStartDate: Date = Date()
    private var previousPedometerData: PedometerData?
    private var yawDataBuffer: [YawData] = []
        
    fileprivate var currentInertialState: InertialState!
    
    weak var stateStore: Store<LibraryState>!
    
    public weak var delegate:CCInertialDelegate?
    
    init(stateStore: Store<LibraryState>) {
        super.init()
        
        self.stateStore = stateStore
        
        currentInertialState = InertialState(isEnabled: false, interval: 0)
        
        stateStore.subscribe(self)
    }
    
    internal func startCountingSteps() {
        
        if CMPedometer.isStepCountingAvailable (){
            
            pedometerStartDate = Date()
            
            previousPedometerData = PedometerData(endDate: pedometerStartDate, numberOfSteps: 0)
            
            pedometer.startUpdates(from: pedometerStartDate) {
                [weak self] pedometerData, error in
                guard let pedometerData = pedometerData, error == nil else {
                    
                    Log.error("Received: \(error.debugDescription)")
                    
                    return
                }
                
                DispatchQueue.main.async {
                    let endDate = pedometerData.endDate
                    let numberOfSteps = pedometerData.numberOfSteps.intValue
                    
                    if let previousPedometerData = self?.previousPedometerData {
                        if numberOfSteps != previousPedometerData.numberOfSteps {
                            
                            let periodBetweenStepCounts:TimeInterval = endDate.timeIntervalSince1970 - previousPedometerData.endDate.timeIntervalSince1970
                            
                            let stepsBetweenStepCounts = numberOfSteps - previousPedometerData.numberOfSteps
                            
                            let timeIntervals = TimeInterval(periodBetweenStepCounts / Double(stepsBetweenStepCounts))
                            
                            Log.debug("Step count: \(numberOfSteps), previous: \(previousPedometerData.numberOfSteps), Period between step counts: \(periodBetweenStepCounts), Steps in-between: \(stepsBetweenStepCounts), Timeintervals: \(timeIntervals), Previous timestamp: \(previousPedometerData.endDate.timeIntervalSince1970), Current timestamp: \(endDate.timeIntervalSince1970)")
                            
                            for i in  1 ... stepsBetweenStepCounts {
                                let tempTimePeriod = TimeInterval(Double(i) * timeIntervals)
                                let tempTimeStamp = previousPedometerData.endDate.timeIntervalSince1970 + tempTimePeriod
                                
                                if let yawDataBuffer = self?.yawDataBuffer {
                                    if let tempYaw = self?.findFirstSmallerYaw(yawArray: yawDataBuffer, timeInterval: tempTimeStamp){
                                        Log.debug ("Step count: \(i), Time period: \(tempTimePeriod), Timestamp: \(tempTimeStamp), Yaw value: \(String(describing: tempYaw.yaw))")
                                        
                                        let stepDate = Date(timeIntervalSince1970: tempTimeStamp)
                                        
                                        if let angle = self?.rad2deg(tempYaw.yaw) {
                                            self?.delegate?.receivedStep(date: stepDate, angle: angle)
                                        }
                                    }
                                }
                            }
                            
                            self?.previousPedometerData = PedometerData (endDate: pedometerData.endDate,
                                                                         numberOfSteps: numberOfSteps)
                        }
                    }
                }
            }
        }
    }
    
    private func startMotionUpdates() {
        if motion.isDeviceMotionAvailable {
//            self.motion.showsDeviceMovementDisplay = true // need to double check the behaviour on this one
            self.motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: OperationQueue.main, withHandler: { (deviceMotion, error) in
                
                guard let data = deviceMotion, error == nil else {
                    
                    let cmError = error as? CMError
                    
                    Log.error("Received: \(cmError.debugDescription)")
                    
                    return
                }
                
                let yawValue = data.attitude.yaw
                let yawData = YawData(yaw: yawValue, date: Date())
                
                    Log.debug("Yaw:\(yawData.yaw), Timestamp: \(yawData.date.timeIntervalSince1970), Interval: \(self.motion.deviceMotionUpdateInterval )")
                
                self.yawDataBuffer.append(yawData)
            })
        }
    }

    private func setInterval (time: TimeInterval){
        self.motion.deviceMotionUpdateInterval = time
    }
    
    private func findFirstSmallerYaw (yawArray:[YawData], timeInterval: TimeInterval) -> YawData?{
        for (index, yaw) in yawArray.reversed().enumerated() {
            //            Log.debug("Yaw time interval: \(yaw.date.timeIntervalSince1970), Time interval: \(timeInterval)")
            if yaw.date.timeIntervalSince1970 < timeInterval {
                yawDataBuffer.removeSubrange(0 ... (yawArray.count - index - 1))
//                Log.debug("Yaw index: \(index)")
//                Log.debug("Index: \(String(describing: yawArray.firstIndex(where: {item in item.date.timeIntervalSince1970 == yaw.date.timeIntervalSince1970})))")
//                Log.debug("Index reverse engineered: \(yawArray.count - index - 1)")
//                Log.debug("Array count: \(yawArray.count)")
                return yaw
            }
        }
        return nil
    }
    
    private func rad2deg(_ number: Double) -> Double {
        return number * 180 / .pi
    }
    
    internal func start () {
        Log.debug("Starting intertial")
        
        startCountingSteps()
        startMotionUpdates()
    }
    
    internal func stop () {
        Log.debug("Stopping inertial")
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
    }
}

// MARK:- StoreSubscriber delegate
extension CCInertial: StoreSubscriber {
    public func newState(state: LibraryState) {
        if let newInertialState = state.intertialState {
            
            Log.debug("new state is: \(newInertialState)")
            
            if newInertialState != self.currentInertialState {
                Log.debug("new state is: \(newInertialState)")
                
                if let interval = newInertialState.interval {
                    setInterval(time: Double(interval) / 1000)
                }

                if let isInertialEnabled = newInertialState.isEnabled {
                    if isInertialEnabled && !self.currentInertialState.isEnabled! {
                        start()
                    }
                
                    if !isInertialEnabled && self.currentInertialState.isEnabled! {
                        stop()
                    }
                }

                self.currentInertialState = newInertialState
            }
        }
    }
}
