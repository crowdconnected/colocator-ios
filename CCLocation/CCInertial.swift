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
    
    public weak var delegate: CCInertialDelegate?
    
    init(stateStore: Store<LibraryState>) {
        super.init()
        
        self.stateStore = stateStore
        currentInertialState = InertialState(isEnabled: false, interval: 0)
        stateStore.subscribe(self)
    }
    
    internal func startCountingSteps() {
        if !CMPedometer.isStepCountingAvailable() { return }
        
        pedometerStartDate = Date()
        previousPedometerData = PedometerData(endDate: pedometerStartDate, numberOfSteps: 0)
        
        pedometer.startUpdates(from: pedometerStartDate) { [weak self] pedometerData, error in
            guard let pedometerData = pedometerData, error == nil else {
                Log.error("Received: \(error.debugDescription)")
                return
            }
            
            DispatchQueue.main.async {
                self?.handleStepsSinceLastCount(fromPedometerData: pedometerData)
            }
        }
    }
    
    private func startMotionUpdates() {
        if !motion.isDeviceMotionAvailable { return }
        
        // need to double check the behaviour on this one
        // self.motion.showsDeviceMovementDisplay = true
        
        self.motion.startDeviceMotionUpdates(using: .xArbitraryZVertical,
                                             to: OperationQueue.main,
                                             withHandler: { (deviceMotion, error) in
            guard let data = deviceMotion, error == nil else {
                let cmError = error as? CMError
                
                Log.error("Received: \(cmError.debugDescription)")
                return
            }
            
            let yawValue = data.attitude.yaw
            let yawData = YawData(yaw: yawValue, date: Date())
            
            Log.debug("""
                Pedometer: Yaw: \(yawData.yaw)
                Timestamp: \(yawData.date.timeIntervalSince1970)
                Interval: \(self.motion.deviceMotionUpdateInterval )
                """)
            
            self.yawDataBuffer.append(yawData)
            
            let bufferSize = CCInertialConstants.bufferSize
            let cutOff = CCInertialConstants.cutOff
            
            if self.yawDataBuffer.count >= bufferSize {
                let upperLimit = bufferSize - cutOff - 1
                self.yawDataBuffer.removeSubrange(0 ... upperLimit)
            }
        })
    }

    private func setInterval(time: TimeInterval) {
        self.motion.deviceMotionUpdateInterval = time
    }
    
    private func findFirstSmallerYaw(yawArray: [YawData], timeInterval: TimeInterval) -> YawData? {
        for (index, yaw) in yawArray.reversed().enumerated() {
            Log.debug("""
                Pedometer: Yaw time interval: \(yaw.date.timeIntervalSince1970)
                Time interval: \(timeInterval)
                """)
            
            if yaw.date.timeIntervalSince1970 < timeInterval {
                let upperLimit = yawArray.count - index - 1
                yawDataBuffer.removeSubrange(0 ... upperLimit)
                return yaw
            }
        }
        return nil
    }
    
    private func rad2deg(_ number: Double) -> Double {
        return number * 180 / .pi
    }
    
    internal func start() {
        if #available(iOS 11.0, *) {
            let pedometerAuthStatus = CMPedometer.authorizationStatus()
            
            if pedometerAuthStatus == .authorized || pedometerAuthStatus == .notDetermined {
                Log.debug("Starting intertial")
                
                startCountingSteps()
                startMotionUpdates()
            } else {
                Log.debug("Authorisation status is .denied or .restriced, no inertial updates requested")
            }
        } else {
            Log.debug("Starting intertial")
            
            startCountingSteps()
            startMotionUpdates()
        }
    }
    
    internal func stop() {
        Log.debug("Stopping inertial")
        
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
    }
    
    private func handleStepsSinceLastCount(fromPedometerData pedometerData: CMPedometerData) {
        guard let tempPreviousPedometerData = previousPedometerData else {
            return
        }
        
        let endDate = pedometerData.endDate
        let numberOfSteps = pedometerData.numberOfSteps.intValue
        
        if tempPreviousPedometerData.numberOfSteps != numberOfSteps {
            let periodBetweenStepCounts = getPeriodBetween(recentDate: endDate,
                                                           oldDate: tempPreviousPedometerData.endDate)
            let stepsBetweenStepCounts = numberOfSteps - tempPreviousPedometerData.numberOfSteps
            let oneStepTimeInterval = TimeInterval(periodBetweenStepCounts / Double(stepsBetweenStepCounts))
            
            Log.debug("""
                Pedometer:
                Step count: \(numberOfSteps)
                Previous step count: \(tempPreviousPedometerData.numberOfSteps)
                Period between step counts: \(periodBetweenStepCounts)
                Steps in-between: \(stepsBetweenStepCounts)
                Time interval per step: \(oneStepTimeInterval)
                Current timestamp: \(endDate.timeIntervalSince1970)
                Previous timestamp: \(tempPreviousPedometerData.endDate.timeIntervalSince1970)
                """)
            
            handleAndReceiveEachStep(totalSteps: stepsBetweenStepCounts,
                                     oneStepTimeInterval: oneStepTimeInterval,
                                     previousPedometerData: tempPreviousPedometerData)
            previousPedometerData = PedometerData (endDate: pedometerData.endDate,
                                                   numberOfSteps: numberOfSteps)
        }
    }
    
    private func handleAndReceiveEachStep(totalSteps: Int,
                                          oneStepTimeInterval: TimeInterval,
                                          previousPedometerData: PedometerData) {
        for i in  1 ... totalSteps {
            let tempTimePeriod = TimeInterval(Double(i) * oneStepTimeInterval)
            let tempTimeStamp = previousPedometerData.endDate.timeIntervalSince1970 + tempTimePeriod
            
            guard let tempYaw = findFirstSmallerYaw(yawArray: yawDataBuffer, timeInterval: tempTimeStamp) else {
                return
            }
            
            Log.debug ("""
                Pedometer: Step count: \(i)
                Time period: \(tempTimePeriod)
                Timestamp: \(tempTimeStamp)
                Yaw value: \(String(describing: tempYaw.yaw))
                """)
            
            let stepDate = Date(timeIntervalSince1970: tempTimeStamp)
            let angle = rad2deg(tempYaw.yaw)
            delegate?.receivedStep(date: stepDate, angle: angle)
        }
    }
    
    private func getPeriodBetween(recentDate date1: Date, oldDate date2: Date) -> TimeInterval {
        return date1.timeIntervalSince1970 - date2.timeIntervalSince1970
    }
}

// MARK:- StoreSubscriber delegate
extension CCInertial: StoreSubscriber {
    
    public func newState(state: LibraryState) {
        guard let newInertialState = state.intertialState else {
            return
        }
        
        Log.debug("Pedometer: New state is: \(newInertialState)")
        
        if newInertialState != currentInertialState {
            if let interval = newInertialState.interval {
                setInterval(time: Double(interval) / 1000)
            }

            updateCurrentInertialStateActivity(newState: newInertialState)
            currentInertialState = newInertialState
        }
    }
    
    private func updateCurrentInertialStateActivity(newState: InertialState) {
        guard let isInertialEnabled = newState.isEnabled else {
            return
        }
        
        if isInertialEnabled && !self.currentInertialState.isEnabled! {
            start()
        }
        if !isInertialEnabled && self.currentInertialState.isEnabled! {
            stop()
        }
    }
}
