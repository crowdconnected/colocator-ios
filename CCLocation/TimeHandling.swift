//
//  TimeHandling.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 09/03/2018.
//  Copyright © 2018 Crowd Connected. All rights reserved.
//

import Foundation
import ReSwift
import TrueTime

public protocol TimeHandlingDelegate: class {
    func newTrueTimeAvailable(trueTime: Date, timeIntervalSinceBootTime: TimeInterval, systemTime: Date, lastRebootTime: Date)
}

class TimeHandling {

    public weak var delegate: TimeHandlingDelegate?

    let trueTimeClient : TrueTimeClient
    var isFetchingTrueTime : Bool = false

    init() {
        trueTimeClient = TrueTimeClient.sharedInstance
        trueTimeClient.start()
    }
    
    public static let shared : TimeHandling = {
        let instance = TimeHandling()
        return instance
    } ()
    
    static func getCurrentTimePeriodSince1970(stateStore: Store<LibraryState>) -> TimeInterval? {
        let currentTime = timeIntervalSinceBoot()
//        Log.verbose("TIME INTERVAL SINCE BOOT: \(currentTime)")

        if let bootTimeAtLastTrueTime = stateStore.state.ccRequestMessagingState.libraryTimeState?.bootTimeIntervalAtLastTrueTime{
            
            let timeIntervalPast = currentTime - bootTimeAtLastTrueTime
            
            let currentTimePeriodSince1970 = (stateStore.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime?.timeIntervalSince1970)! + timeIntervalPast
            
//            Log.verbose("TIME INTERVAL: \(currentTimePeriodSince1970)")
            
            return currentTimePeriodSince1970
        }
        
        return nil
    }
    
    static func timeIntervalSinceBoot() -> TimeInterval {

        let timeIntervalSinceBoot = ProcessInfo.processInfo.systemUptime
//        Log.verbose("time interval since boot: \(timeIntervalSinceBoot)")
        
        return timeIntervalSinceBoot
    }
    
    func fetchTrueTime() {
        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self = self else {
                return
            }
            self.fetchTrueTimeInBackground()
        }
    }
    
    func fetchTrueTimeInBackground(){
        if (!isFetchingTrueTime){
            isFetchingTrueTime = true
            
            trueTimeClient.fetchIfNeeded(success: { (referenceTime) in
                NSLog("[Colocator] True time: " + referenceTime.now().description)
                let lastRebootTime: Date = referenceTime.now().addingTimeInterval(TimeHandling.timeIntervalSinceBoot())
                
                self.delegate?.newTrueTimeAvailable(trueTime: referenceTime.now(), timeIntervalSinceBootTime: TimeHandling.timeIntervalSinceBoot(), systemTime: Date.init(), lastRebootTime: lastRebootTime)
                
                self.isFetchingTrueTime = false
            }, failure: { (error) in
                Log.error("[Colocator] Truetime error! " + error.description)
                
                self.isFetchingTrueTime = false
            })
        }
    }

    func isRebootTimeSame (stateStore: Store<LibraryState>, ccSocket: CCSocket?) -> Bool {
        
        if !isFetchingTrueTime {

            guard let lastBootTimeInterval = stateStore.state.ccRequestMessagingState.libraryTimeState?.bootTimeIntervalAtLastTrueTime else {
                return false
            }
            
            guard let lastSystemTime = stateStore.state.ccRequestMessagingState.libraryTimeState?.systemTimeAtLastTrueTime else {
                return false
            }
            
            let currentBootTimeInterval = TimeHandling.timeIntervalSinceBoot()
            
            let currentTime = Date()
            
            let beetweenBootsTimeInterval = currentBootTimeInterval - lastBootTimeInterval
            
            let beetweenSystemsTimeInterval = currentTime.timeIntervalSince(lastSystemTime)
            
            let isSame = abs(beetweenBootsTimeInterval - beetweenSystemsTimeInterval) < 30
            
            Log.debug("Comparing bootTimeIntervalDiff \(String(describing: beetweenBootsTimeInterval)) with systemTimeInterval \(String(describing: beetweenSystemsTimeInterval)) result = \(isSame)")
            
            // if there has been some drift or similar fetch a new true time
            if !isSame {
                fetchTrueTime()
            }
            
            return isSame
        } else {
            return false
        }
    }
}
