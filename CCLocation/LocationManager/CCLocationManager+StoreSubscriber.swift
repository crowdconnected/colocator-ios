//
//  CCLocationManager+StoreSubscriber.swift
//  CCLocation
//
//  Created by Mobile Developer on 04/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import CoreLocation
import Foundation
import ReSwift

// Extension Store Subscriber

extension CCLocationManager: StoreSubscriber {
    
    func handleGEOState(_ newGEOState: CurrentGEOState) {
        if let isStandardGEOEnabled = newGEOState.isStandardGEOEnabled {
            if isStandardGEOEnabled {
                
                if let activityType = newGEOState.activityType {
                    locationManager.activityType = activityType
                }
                
                if let desiredAccuracy = newGEOState.desiredAccuracy {
                    locationManager.desiredAccuracy = CLLocationAccuracy(desiredAccuracy)
                }
                
                if let distanceFilter = newGEOState.distanceFilter {
                    locationManager.distanceFilter = CLLocationDistance(distanceFilter)
                }
                
                if let pausesUpdates = newGEOState.pausesUpdates {
                    locationManager.pausesLocationUpdatesAutomatically = pausesUpdates
                }
                
                // in case an offTime has been stored in state state store last time round
                if let offTime = newGEOState.offTime {
                    if offTime <= Date() {
                        Log.verbose("GEOTIMER offTime \(offTime) occured before current time \(Date()), resetting offTime")
                        DispatchQueue.main.async {self.stateStore.dispatch(SetGEOOffTimeEnd(offTimeEnd: nil))}
                    } else {
                        Log.verbose("GEOTIMER offTime \(offTime) occured after current date \(Date()), keeping offTime and doing nothing")
                        // do nothing
                    }
                    // and in case there is not offTime, just start the location manager for maxRuntime
                } else {
                    Log.verbose("GEOTIMER startUpdatingLocation no offTime available")
                    locationManager.startUpdatingLocation()
                    
                    Log.verbose("Enabled GEO settings are activityType:\(locationManager.activityType), desiredAccuracy: \(locationManager.desiredAccuracy), distanceFilter: \(locationManager.distanceFilter), pausesUpdates: \(locationManager.pausesLocationUpdatesAutomatically)")
                    
                    if let maxRunTime = newGEOState.maxRuntime {
                        if (self.maxRunGEOTimer == nil){
                            Log.verbose("GEOTIMER start maxGEORunTimer \(maxRunTime)")
                            self.maxRunGEOTimer = Timer.scheduledTimer(timeInterval: TimeInterval(maxRunTime / 1000), target: self, selector: #selector(stopLocationUpdates), userInfo: nil, repeats: false)
                        }
                    } else {
                        if self.maxRunGEOTimer != nil {
                            self.maxRunGEOTimer?.invalidate()
                            self.maxRunGEOTimer = nil
                        }
                    }
                }
            } else {
                locationManager.stopUpdatingLocation()
                
                if self.maxRunGEOTimer != nil {
                    self.maxRunGEOTimer?.invalidate()
                    self.maxRunGEOTimer = nil
                }
                
                if newGEOState.offTime != nil {
                    DispatchQueue.main.async {self.stateStore.dispatch(SetGEOOffTimeEnd(offTimeEnd: nil))}
                }
            }
        }
    }
    
    public func newState(state: CurrentLocationState) {
        
        if let newGEOState = state.currentGEOState {
            
            let wakeupState = stateStore.state.locationSettingsState.currentLocationState?.wakeupState?.ccWakeup
            
            if newGEOState != self.currentGEOState || wakeupState == CCWakeup.notifyWakeup {
                
                Log.debug("New state is: \(newGEOState)")
                
                self.currentGEOState = newGEOState
                
                if let isSignificantUpdates = newGEOState.isSignificantLocationChangeMonitoringState {
                    if isSignificantUpdates {
                        startReceivingSignificantLocationChanges()
                    } else {
                        stopReceivingSignificantLocationChanges()
                    }
                }
                
                handleGEOState(newGEOState)
            }
        }
        
        if let newiBeaconMonitoringState = state.currentiBeaconMonitoringState {
            
            if newiBeaconMonitoringState != self.currentiBeaconMonitoringState {
                self.currentiBeaconMonitoringState = newiBeaconMonitoringState
                self.updateMonitoringForRegions()
            }
        }
        
        if let newBeaconState = state.currentBeaconState {
            
            let wakeupState = stateStore.state.locationSettingsState.currentLocationState?.wakeupState?.ccWakeup
            
            if newBeaconState != currentBeaconState || wakeupState == CCWakeup.notifyWakeup {
                
                currentBeaconState = newBeaconState
                Log.debug("new state is: \(newBeaconState), with CCWakeup \(String(describing: wakeupState))")
                
                let isIBeaconRangingEnabled = currentBeaconState.isIBeaconRangingEnabled
                let isEddystoneScanEnabled = currentBeaconState.isEddystoneScanningEnabled
                
                if isIBeaconRangingEnabled != nil || isEddystoneScanEnabled != nil {
                    
                    // managing cycling of Beacon discovery
                    //                        if currentBeaconState.isCyclingEnabled! {
                    if maxBeaconRunTimer == nil && minOffTimeBeaconTimer == nil {
                        startBeaconScanning()
                    }
                    
                    
                    //                        if let maxRuntime = currentBeaconState.maxRuntime {
                    //                            Log.verbose("Cycling: setting maxRuntime timer \(maxRuntime) at start")
                    //                            if maxBeaconRunTimer == nil {
                    //                                maxBeaconRunTimer = Timer.scheduledTimer(timeInterval: TimeInterval(maxRuntime / 1000), target: self, selector: #selector(self.stopRangingBeaconsFor), userInfo: nil, repeats: false)
                    //                            }
                    //                        }
                    //                    } else {
                    //                        // in case an offTime has been stored in state state store last time round
                    //                        if let offTime = currentBeaconState.offTime {
                    //                            if offTime <= Date() {
                    //                                Log.verbose("BEACONTIMER after offTime")
                    //                                stateStore.dispatch(SetiBeaconOffTimeEndAction(offTimeEnd: nil))
                    //                            } else {
                    //                                Log.verbose("BEACONTIMER do nothing with beacon offTime")
                    //                            }
                    //                            // and in case there is not offTime, just start the location manager
                    //                        } else {
                    //                            Log.verbose("BEACONTIMER no offTime available")
                    //                            updateRangingIBeacons()
                    //                            if let maxRuntime = currentBeaconState.maxRuntime {
                    //                                if maxBeaconRunTimer == nil {
                    //                                    Log.verbose("IBEACONTIMER start maxRunTimer \(maxRuntime)")
                    //                                    maxBeaconRunTimer = Timer.scheduledTimer(timeInterval: TimeInterval(maxRuntime / 1000), target: self, selector: #selector(stopRangingBeaconsFor), userInfo: nil, repeats: false)
                    //                                    stateStore.dispatch(SetiBEaconMaxOnTimeStartAction(maxOnTimeStart: Date()))
                    //                                }
                    //                            }
                    //                        }
                    
                    // manage timer for beacon window size duration
                    
                    if let beaconWindowSizeDuration = currentBeaconState.filterWindowSize {
                        // initialise time on filterWindowSize being available
                        if beaconWindowSizeDurationTimer == nil {
                            Log.verbose("BEACONWINDOWSIZETIMER start beaconWindowSizeDuration timer with: \(beaconWindowSizeDuration)")
                            beaconWindowSizeDurationTimer = Timer.scheduledTimer(timeInterval: TimeInterval(beaconWindowSizeDuration / 1000), target: self, selector: #selector(processBeaconTables), userInfo: nil, repeats: true)
                        }
                    } else {
                        // clean up timer
                        if  beaconWindowSizeDurationTimer != nil {
                            beaconWindowSizeDurationTimer?.invalidate()
                            beaconWindowSizeDurationTimer = nil
                        }
                    }
                } else {
                    
                    // clean up timers
                    if maxBeaconRunTimer != nil {
                        maxBeaconRunTimer?.invalidate()
                        maxBeaconRunTimer = nil
                    }
                    
                    if minOffTimeBeaconTimer != nil {
                        minOffTimeBeaconTimer?.invalidate()
                        minOffTimeBeaconTimer = nil
                    }
                    
                    stopRangingBeaconsFor(timer: nil)
                }
            }
        }
        
        if let newWakeupNotificationState = state.wakeupState {
            Log.debug("Got a wake up state reported, state is: \(newWakeupNotificationState)")
            if newWakeupNotificationState != wakeupState {
                wakeupState = newWakeupNotificationState
                Log.debug("new state is: \(newWakeupNotificationState)")
                if wakeupState.ccWakeup == CCWakeup.notifyWakeup{
                    DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.idle))}
                }
            }
        }
    }
}
