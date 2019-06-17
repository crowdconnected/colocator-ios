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
    
    private var isInertialRunning = false
    
    fileprivate var currentInertialState: InertialState!
    
    weak var stateStore: Store<LibraryState>!
    
    public weak var delegate:CCInertialDelegate?

    init(stateStore: Store<LibraryState>) {
        super.init()
        
        self.stateStore = stateStore
        
        currentInertialState = InertialState(isEnabled: true, interval: 0)
        
        stateStore.subscribe(self)
    }
    
    internal func startCountingSteps() {
        
        pedometerStartDate = Date()
        
        previousPedometerData = PedometerData(endDate: pedometerStartDate, numberOfSteps: 0)
        
        pedometer.startUpdates(from: pedometerStartDate) {
            [weak self] pedometerData, error in
            guard let pedometerData = pedometerData, error == nil else { return }
            
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
                                
                                    self?.delegate?.receivedStep(date: tempYaw.date, angle: tempYaw.yaw)
                                }
                            }
                        }
                        
                        self?.previousPedometerData = PedometerData (endDate: pedometerData.endDate,
                                                                     numberOfSteps: numberOfSteps)
                        
//                        self?.yawDataBuffer.removeAll()
                    }
                }
//                let dataStringPart1 = "Pedometer data: " + start + end + receivedTime + numberOfSteps
            }
        }
    }
    
    private func startMotionUpdates() {
        if motion.isDeviceMotionAvailable {
            self.motion.deviceMotionUpdateInterval = 1.0 / 5.0
            self.motion.showsDeviceMovementDisplay = true // need to double check the behaviour on this one
            self.motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: OperationQueue.main, withHandler: { (data, error) in
                if let validData = data {
                    
                    let yawValue = validData.attitude.yaw
                    let yawData = YawData(yaw: yawValue, date: Date())
                    
                    Log.debug("Yaw:\(yawData.yaw), Timestamp: \(yawData.date.timeIntervalSince1970)")
                    
                    self.yawDataBuffer.append(yawData)
                }
            })
        }
    }
    
    private func findFirstSmallerYaw (yawArray:[YawData], timeInterval: TimeInterval) -> YawData?{
        for (index, yaw) in yawArray.reversed().enumerated() {
//            Log.debug("Yaw time interval: \(yaw.date.timeIntervalSince1970), Time interval: \(timeInterval)")
            if yaw.date.timeIntervalSince1970 < timeInterval {
                yawDataBuffer.removeSubrange(0 ... index)
                Log.debug("Yaw index: \(index)")
                return yaw
            }
        }
        return nil
    }

    internal func start () {
        Log.debug("Starting intertial")
        
        if !isInertialRunning{
            startCountingSteps()
            startMotionUpdates()
            isInertialRunning = true
        }
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
                self.currentInertialState = newInertialState
                Log.debug("new state is: \(newInertialState)")
                
                if let isInertialEnabled = newInertialState.isEnabled {
                    if isInertialEnabled {
                        start()
                    } else {

// just for testing !!!!!!!!!!!!

                        start()
                        
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                    }
                }
            }
        }
    }
}
