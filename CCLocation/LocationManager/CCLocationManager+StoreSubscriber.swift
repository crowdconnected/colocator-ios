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
    
    public func newState(state: CurrentLocationState) {
        let wakeUpState = stateStore?.state.locationSettingsState.currentLocationState?.wakeupState?.ccWakeup
        let isWakeUpNotification = wakeUpState == CCWakeup.notifyWakeup
        
        // Geo State
        

        if let newGEOState = state.currentGEOState,
           (newGEOState != self.currentGEOState || isWakeUpNotification) {
            Log.verbose("New GEOState \n \(String(describing: newGEOState))")

            DispatchQueue.main.async { [weak self] in
                self?.currentGEOState = newGEOState
                self?.updateSignificantUpdatesForGEOState(newGEOState)
                self?.updateGEOState(newGEOState)
            }
        }
        
        // Geofence State
        

        if let newGeofencesState = state.currentGeofencesMonitoringState,
           newGeofencesState != self.currentGeofencesMonitoringState {
            Log.verbose("New GeofencesMonitoringState \n \(String(describing: newGeofencesState))")

            DispatchQueue.main.async { [weak self] in
                self?.currentGeofencesMonitoringState = newGeofencesState
                self?.updateMonitoringGeofences()
            }
         }
        
        // Beacon Monitoring State
        

        if let newiBeaconMonitoringState = state.currentiBeaconMonitoringState,
           newiBeaconMonitoringState != self.currentiBeaconMonitoringState {
            Log.verbose("New iBeaconMonitoringState \n \(String(describing: newiBeaconMonitoringState))")

            DispatchQueue.main.async { [weak self] in
                self?.currentiBeaconMonitoringState = newiBeaconMonitoringState
                self?.updateMonitoringForRegions()
            }
        }
        
        // Beacon State


        if let newBeaconState = state.currentBeaconState,
           (newBeaconState != currentBeaconState || isWakeUpNotification) {
            Log.verbose("New BeaconState \n \(String(describing: newBeaconState))")

            DispatchQueue.main.async { [weak self] in
                self?.currentBeaconState = newBeaconState
                let isIBeaconRangingEnabled = self?.currentBeaconState.isIBeaconRangingEnabled
                let isEddystoneScanEnabled = self?.currentBeaconState.isEddystoneScanningEnabled
                
                if isIBeaconRangingEnabled != nil || isEddystoneScanEnabled != nil {
                    //TODO Add maxRunTime and minOffTime dependency
                    self?.startBeaconScanning()

                    self?.updateWindowSizeFilter()
                } else {
                    self?.cleanUpBeaconTimers()
                    self?.stopRangingBeaconsFor()
                }
            }
        }
        
        // WakeUp State
        

        if let newWakeupNotificationState = state.wakeupState,
           newWakeupNotificationState != wakeupState {
            Log.verbose("New WakeUpState \n \(String(describing: newWakeupNotificationState))")

            DispatchQueue.main.async { [weak self] in
                self?.wakeupState = newWakeupNotificationState
                if self?.wakeupState.ccWakeup == CCWakeup.notifyWakeup {
                    self?.stateStore?.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.idle))
                }
            }
        }
    }
    
    func updateSignificantUpdatesForGEOState(_ newGEOState: CurrentGEOState) {
        guard let isSignificantUpdates = newGEOState.isSignificantLocationChangeMonitoringState else {
            return
        }
        
        if isSignificantUpdates {
            startReceivingSignificantLocationChanges()
        } else {
            stopReceivingSignificantLocationChanges()
        }
    }
    
    func updateGEOState(_ newGEOState: CurrentGEOState) {
        guard let isStandardGEOEnabled = newGEOState.isStandardGEOEnabled else {
            return
        }
        
        if isStandardGEOEnabled {
            updateSettingsForGEOState(newGEOState)
            updateTimersForGEOState(newGEOState)
        } else {
            disableGeoStandardLocation(newGEOState: newGEOState)
        }
    }
    
    func updateSettingsForGEOState(_ newGEOState: CurrentGEOState) {
        if let activityType = newGEOState.activityType {
            locationManager?.activityType = activityType
        }
        if let desiredAccuracy = newGEOState.desiredAccuracy {
            locationManager?.desiredAccuracy = CLLocationAccuracy(desiredAccuracy)
        }
        if let distanceFilter = newGEOState.distanceFilter {
            locationManager?.distanceFilter = CLLocationDistance(distanceFilter)
        }
        #if RELEASE
        if let pausesUpdates = newGEOState.pausesUpdates {
            locationManager?.pausesLocationUpdatesAutomatically = pausesUpdates
        }
        #endif
    }
    
    func updateTimersForGEOState(_ newGEOState: CurrentGEOState) {
        // If offTime has been stored in state store at last update
        if let offTime = newGEOState.offTime {
            if offTime <= Date() {
                Log.debug("GeoTimer offTime passed and reset to nil")
                DispatchQueue.main.async { [weak self] in
                    self?.stateStore?.dispatch(SetGEOOffTimeEnd(offTimeEnd: nil))
                }
            }
            
            // If there's no offTime, start the location manager for maxRuntime
        } else {
            Log.info("Start collecting GEO")

            locationManager?.startUpdatingLocation()
            isContinuousGEOCollectionActive = true
            
            if let maxRunTime = newGEOState.maxRuntime {
                if self.maxRunGEOTimer == nil {
                    startMaxRunTimeGeoTimer(maxRunTime: maxRunTime)
                }
            } else {
                stopMaxRunTimeGeoTimer()
            }
        }
    }
    
    func startMaxRunTimeGeoTimer(maxRunTime: UInt64) {
        Log.verbose("Start maxGEORunTimer \(maxRunTime)")
        
        self.maxRunGEOTimer = Timer.scheduledTimer(timeInterval: TimeInterval(maxRunTime / 1000),
                                                   target: self,
                                                   selector: #selector(stopLocationUpdates),
                                                   userInfo: nil,
                                                   repeats: false)
    }
    
    func stopMaxRunTimeGeoTimer() {
        self.maxRunGEOTimer?.invalidate()
        self.maxRunGEOTimer = nil
    }
    
    func disableGeoStandardLocation(newGEOState: CurrentGEOState) {
        locationManager?.stopUpdatingLocation()
                  
        if self.maxRunGEOTimer != nil {
            self.maxRunGEOTimer?.invalidate()
            self.maxRunGEOTimer = nil
        }
      
        if newGEOState.offTime != nil {
            DispatchQueue.main.async { [weak self] in
                self?.stateStore?.dispatch(SetGEOOffTimeEnd(offTimeEnd: nil))
            }
        }
    }
    
    func cleanUpBeaconTimers() {
        if maxBeaconRunTimer != nil {
            maxBeaconRunTimer?.invalidate()
            maxBeaconRunTimer = nil
        }
        if minOffTimeBeaconTimer != nil {
            minOffTimeBeaconTimer?.invalidate()
            minOffTimeBeaconTimer = nil
        }
    }
    
    func updateWindowSizeFilter() {
        if let beaconWindowSizeDuration = currentBeaconState.filterWindowSize {
            if beaconWindowSizeDurationTimer == nil {
                startWindowSizeTimer(duration: beaconWindowSizeDuration)
            }
        } else {
            stopWindowSizeTimer()
        }
    }
    
    func startWindowSizeTimer(duration: UInt64) {
        Log.verbose("BeaconWindowSize timer starts with duration: \(duration)")

        beaconWindowSizeDurationTimer = Timer.scheduledTimer(timeInterval: TimeInterval(duration / 1000),
                                                             target: self,
                                                             selector: #selector(processBeaconTables),
                                                             userInfo: nil,
                                                             repeats: true)
    }
    
    func stopWindowSizeTimer() {
        beaconWindowSizeDurationTimer?.invalidate()
        beaconWindowSizeDurationTimer = nil
    }
}
