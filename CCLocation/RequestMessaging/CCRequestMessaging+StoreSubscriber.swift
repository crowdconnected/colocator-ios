//
//  CCRequestMessaging+StoreSubscriber.swift
//  CCLocation
//
//  Created by Mobile Developer on 04/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import Foundation
import ReSwift

// Extension Store Subscriber

extension CCRequestMessaging: StoreSubscriber {
    
    public func newState(state: CCRequestMessagingState) {
        
        Log.debug("New state is: \(state)")
        
        if let webSocketState = state.webSocketState {
            if webSocketState != currentWebSocketState{
                currentWebSocketState = webSocketState
                
                if webSocketState.connectionState == ConnectionState.online {
                    
                    let aliases: Dictionary? = UserDefaults.standard.dictionary(forKey: CCSocketConstants.ALIAS_KEY)
                    
                    if (aliases != nil){
                        processAliases(aliases: aliases! as! Dictionary<String, String>)
                    }
                }
            }
        }
        
        // if we have a radioSilenceTimer and if its state has changed
        if let newTimerState = state.radiosilenceTimerState, newTimerState != currentRadioSilenceTimerState {
            actualizeTimerState(newState: newTimerState)
        }
        
        if let newLibraryTimeState = state.libraryTimeState {
            if newLibraryTimeState != currentLibraryTimerState {
                
                currentLibraryTimerState = newLibraryTimeState
                
                if let bootTimeInterval = newLibraryTimeState.bootTimeIntervalAtLastTrueTime {
                    
                    let timeDifferenceSinceLastTrueTime = bootTimeInterval - TimeHandling.timeIntervalSinceBoot()
                    
                    if timeDifferenceSinceLastTrueTime > 60 {
                        timeHandling.fetchTrueTime()
                    }
                }
            }
        }
        
        if let newCapabilityState = state.capabilityState {
            if newCapabilityState != currentCapabilityState {
                
                processIOSCapability(locationAuthStatus: newCapabilityState.locationAuthStatus, bluetoothHardware: newCapabilityState.bluetoothHardware, batteryState: newCapabilityState.batteryState, isLowPowerModeEnabled: newCapabilityState.isLowPowerModeEnabled, isLocationServicesEnabled: newCapabilityState.isLocationServicesAvailable)
                
                currentCapabilityState = newCapabilityState
            }
        }
    }
    
    public func actualizeTimerState(newState: TimerState) {
        
        currentRadioSilenceTimerState = newState
        
        if newState.timer == .schedule {
            scheduleTimerWithNewTimerInterval(newState: newState)
        }
        if newState.timer == .running {
            Log.verbose("RADIOSILENCETIMER timer is in running state")
        }
        
//        covers case were app starts from terminated and no timer is available yet
        if timeBetweenSendsTimer == nil {
            
            Log.verbose("RADIOSILENCETIMER timeBetweenSendsTimer == nil, scheduling new timer")
            
            if timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket){
                DispatchQueue.main.async {self.stateStore.dispatch(ScheduleSilencePeriodTimerAction())}
            }
        }
        
        if newState.timer == .invalidate {
            
            Log.verbose("RADIOSILENCETIMER invalidate timer")
            
            if timeBetweenSendsTimer != nil{
                if timeBetweenSendsTimer!.isValid {
                    timeBetweenSendsTimer!.invalidate()
                }
                timeBetweenSendsTimer = nil
            }
            
            DispatchQueue.main.async {self.stateStore.dispatch(TimerStoppedAction())}
        }
    }
    
    public func scheduleTimerWithNewTimerInterval(newState: TimerState) {
        
        if timeBetweenSendsTimer != nil {
            if timeBetweenSendsTimer!.isValid{
                timeBetweenSendsTimer!.invalidate()
            }
        }
        
        if let newTimeInterval = newState.timeInterval {
            if let radioSilenceTimerState = newState.startTimeInterval {
                
                let intervalForLastTimer = TimeHandling.timeIntervalSinceBoot() - radioSilenceTimerState
                Log.verbose("RADIOSILENCETIMER intervalForLastTimer = \(intervalForLastTimer)")
                
                if intervalForLastTimer < Double(Double(newTimeInterval) / 1000) {
                    
                    timeBetweenSendsTimer = Timer.scheduledTimer(timeInterval:TimeInterval(intervalForLastTimer), target: self, selector: #selector(self.sendQueuedClientMessagesTimerFiredOnce), userInfo: nil, repeats: false)
                    DispatchQueue.main.async {self.stateStore.dispatch(TimerRunningAction(startTimeInterval: nil))}
                } else {
                    
                    timeBetweenSendsTimer = Timer.scheduledTimer(timeInterval:TimeInterval(Double(newTimeInterval) / 1000), target: self, selector: #selector(self.sendQueuedClientMessagesTimerFired), userInfo: nil, repeats: true)
                    
                    DispatchQueue.main.async {self.stateStore.dispatch(TimerRunningAction(startTimeInterval: TimeHandling.timeIntervalSinceBoot()))}
                }
            } else {
                
                timeBetweenSendsTimer = Timer.scheduledTimer(timeInterval:TimeInterval(Double(newTimeInterval) / 1000), target: self, selector: #selector(self.sendQueuedClientMessagesTimerFired), userInfo: nil, repeats: true)
                
                DispatchQueue.main.async {self.stateStore.dispatch(TimerRunningAction(startTimeInterval: TimeHandling.timeIntervalSinceBoot()))}
            }
        }
    }
}
