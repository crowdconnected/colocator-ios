//
//  CCLocationManager+RangingBeacons.swift
//  CCLocation
//
//  Created by Mobile Developer on 04/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import CoreLocation
import Foundation

// Extension Ranging Beacons

extension CCLocationManager {
    
    @objc func updateMonitoringForRegions () {
        
        // stop monitoring for regions
        self.stopMonitoringForBeaconRegions()
        
        // then see if we can start monitoring for new region
        
        Log.verbose("------- a list of monitored regions before adding iBeacons -------")
        for monitoredRegion in locationManager.monitoredRegions {
            Log.verbose("region \(monitoredRegion)")
        }
        Log.verbose("------- list end -------")
        
        for region in currentiBeaconMonitoringState.monitoringRegions {
            
            var regionInMonitoredRegions = false
            
            for monitoredRegion in locationManager.monitoredRegions where monitoredRegion is CLBeaconRegion {
                if (monitoredRegion as! CLBeaconRegion).proximityUUID.uuidString == region.proximityUUID.uuidString {
                    regionInMonitoredRegions = true
                }
            }
            
            if (!regionInMonitoredRegions) {
                if (CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self)) {
                    region.notifyEntryStateOnDisplay = true
                    locationManager.startMonitoring(for: region)
                }
            }
        }
    }
    
    func stopMonitoringForBeaconRegions () {
        // first check filter out all regions we are monitoring atm
        let crowdConnectedRegions = locationManager.monitoredRegions.filter {
            return $0 is CLBeaconRegion ? (($0 as! CLBeaconRegion).identifier.range(of: "CC") != nil) : false
        }
        
        // second stop monitoring for beacons that are not included in the current settings
        for region in crowdConnectedRegions where !currentiBeaconMonitoringState.monitoringRegions.contains(region as! CLBeaconRegion) {
            locationManager.stopMonitoring(for: region as! CLBeaconRegion)
        }
    }
    
    @objc func startBeaconScanning() {
        
        // start ibeacon scanning if enabled
        if let isIBeaconEnabledUnwrapped = currentBeaconState.isIBeaconRangingEnabled {
            if isIBeaconEnabledUnwrapped {
                updateRangingIBeacons()
            }
        }
        
        // start eddystone beacon scanning if enabled
        if let isEddystoneScanEnabledUnwrapped = currentBeaconState.isEddystoneScanningEnabled {
            if isEddystoneScanEnabledUnwrapped {
                eddystoneBeaconScanner?.startScanning()
            }
        }
        
        // make sure timers are cleared out
        if minOffTimeBeaconTimer != nil {
            minOffTimeBeaconTimer?.invalidate()
            minOffTimeBeaconTimer = nil
        }
        
        // make sure that scanning finishes when maxRuntime has expired
        if let maxRuntime = currentBeaconState.maxRuntime {
            Log.verbose("Cycling: setting maxRuntime timer \(maxRuntime) in startBeaconScanning()")
            
            if maxBeaconRunTimer != nil {
                maxBeaconRunTimer?.invalidate()
                maxBeaconRunTimer = nil
            }
            maxBeaconRunTimer = Timer.scheduledTimer(timeInterval: TimeInterval(maxRuntime / 1000),
                                                     target: self,
                                                     selector: #selector(self.stopRangingBeaconsFor),
                                                     userInfo: nil,
                                                     repeats: false)
        }
    }
    
    func updateRangingIBeacons() {
        
        Log.debug("updateRangingIBeacons");
        
        // first stop ranging for any CrowdConnected regions
        stopRangingiBeacons(forCurrentSettings: true)
        
        // Then see if we can start ranging for new region
        for region in currentBeaconState.regions {
            
            var regionInRangedRegions = false
            
            for rangedRegion in locationManager.rangedRegions where rangedRegion is CLBeaconRegion {
                if (rangedRegion as! CLBeaconRegion).proximityUUID.uuidString == region.proximityUUID.uuidString {
                    regionInRangedRegions = true
                }
            }
            
            if (!regionInRangedRegions){
                if (CLLocationManager.isRangingAvailable()){
                    locationManager.startRangingBeacons(in: region)
                }
            }
        }
    }
    
    @objc func stopRangingBeaconsFor (timer: Timer!){
        
        // stop scanning for Eddystone beacons
        eddystoneBeaconScanner?.stopScanning()
        
        // stop ranging for iBeacons
        stopRangingiBeacons(forCurrentSettings: false)
        
        // clear timer
        if (maxBeaconRunTimer != nil) {
            maxBeaconRunTimer?.invalidate()
            maxBeaconRunTimer = nil
        }
        
        //        if currentBeaconState.isCyclingEnabled! {
        
        // check whether we have any beacons to scan for
        let isIBeaconEnabled = currentBeaconState.isIBeaconRangingEnabled
        let isEddystoneScanEnabled = currentBeaconState.isEddystoneScanningEnabled
        
        if isIBeaconEnabled != nil || isEddystoneScanEnabled != nil {
            if let minOffTime = currentBeaconState.minOffTime {
                
                Log.verbose("Cycling: setting minOffTime timer \(minOffTime)")
                
                if minOffTimeBeaconTimer != nil {
                    minOffTimeBeaconTimer?.invalidate()
                    minOffTimeBeaconTimer = nil
                }
                minOffTimeBeaconTimer = Timer.scheduledTimer(timeInterval: TimeInterval(minOffTime / 1000),
                                                             target: self,
                                                             selector: #selector(startBeaconScanning),
                                                             userInfo: nil,
                                                             repeats: false)
            }
        }
        
        //        } else {
        //            if let minOffTime = currentBeaconState.minOffTime {
        //
        //                if let maxOnTimeStart = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.maxOnTimeStart {
        //                    if let maxOnTimeInterval = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.maxRuntime {
        //
        //                        let timeIntervalMaxOnTimeStart = Date().timeIntervalSince(maxOnTimeStart)
        //
        //                        if timeIntervalMaxOnTimeStart > TimeInterval(maxOnTimeInterval / 1000) {
        //                            let offTimeEnd = maxOnTimeStart.addingTimeInterval(TimeInterval(maxOnTimeInterval / 1000)).addingTimeInterval(TimeInterval(minOffTime / 1000))
        //
        //                            if (offTimeEnd > Date()) {
        //                                stateStore.dispatch(SetiBeaconOffTimeEndAction(offTimeEnd: offTimeEnd))
        //                            } else {
        //                                // do nothing
        //                            }
        //                        } else {
        //                            let offTimeEnd = Date().addingTimeInterval(TimeInterval(minOffTime / 1000))
        //
        //                            Log.verbose("BEACONTIMER we have a minOffTime of \(offTimeEnd) for Beacons to be set")
        //
        //                            stateStore.dispatch(SetiBeaconOffTimeEndAction(offTimeEnd: offTimeEnd))
        //                        }
        //                    }
        //                } else {
        //                    let offTimeEnd = Date().addingTimeInterval(TimeInterval(minOffTime / 1000))
        //
        //                    Log.verbose("BEACONTIMER we have a minOffTime of \(offTimeEnd) for Beacons to be set")
        //
        //                    stateStore.dispatch(SetiBeaconOffTimeEndAction(offTimeEnd: offTimeEnd))
        //                }
        //            } else {
        //                Log.verbose("BEACONTIMER no min off time, stopping updates")
        //                stateStore.dispatch(SetiBeaconOffTimeEndAction(offTimeEnd: nil))
        //            }
        //        }
    }
    
    func stopRangingiBeacons (forCurrentSettings: Bool) {
        
        // iBeacon first filter for all regions we are ranging in atm
        let crowdConnectedRegions = locationManager.rangedRegions.filter {
            return $0 is CLBeaconRegion ? (($0 as! CLBeaconRegion).identifier.range(of: "CC") != nil) : false
        }
        
        // iterate through all crowdConnectedRegions
        for region in crowdConnectedRegions {
            
            // check if we only want to stop beacons that are not included in the current settings
            if (forCurrentSettings){
                if !currentBeaconState.regions.contains(region as! CLBeaconRegion){
                    locationManager.stopRangingBeacons(in: region as! CLBeaconRegion)
                }
                // else we want to stop ranging for all beacons, because we either received new settings without ranging or the maxRuntime has expired
            } else {
                locationManager.stopRangingBeacons(in: region as! CLBeaconRegion)
            }
        }
    }
    
    // MARK: - PROCESS BEACON AND EDDYBEACON TABLES
    
    @objc func processBeaconTables() {
        processiBeaconTable()
        processEddystoneBeaconTable()
    }
    
    func processiBeaconTable() {
        
        countBeacons()
        guard let beaconsUnwrapped = getAllBeaconsAndDelete() else {
            return
        }
        
        // create a key / value list that creates a unquiqe key for each beacon.
        var newBeacons: [[String:Beacon]] = []
        
        for beacon in beaconsUnwrapped {
            
            var newBeacon: [String:Beacon] = [:]
            
            newBeacon["\(beacon.uuid):\(beacon.major):\(beacon.minor)"] = beacon
            
            newBeacons.append(newBeacon)
        }
        
        // group all identical beacons under the unique key
        let groupedBeacons = newBeacons.group(by: {$0.keys.first!})
        
        var youngestBeaconInWindow: Beacon?
        var beaconsPerWindow : [Beacon] = []
        
        for beaconGroup in groupedBeacons {
            
            let sortedBeaconGroup = beaconGroup.value.sorted(by: {
                
                let value1 = $0.first!.value
                let value2 = $1.first!.value
                
                return value1.timeIntervalSinceBootTime < value2.timeIntervalSinceBootTime
            })
            
            youngestBeaconInWindow = sortedBeaconGroup[0].values.first
            
            beaconsPerWindow.append(youngestBeaconInWindow!)
        }
        
        if let maxObservations = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterMaxObservations {
            
            var sortedValues = beaconsPerWindow.sorted(by: {$0.rssi > $1.rssi})
            
            if (sortedValues.count > Int(maxObservations)) {
                sortedValues = Array(sortedValues.prefix(Int(maxObservations)))
            }
            
            for beacon in sortedValues {
                
                delegate?.receivediBeaconInfo(proximityUUID: UUID(uuidString: beacon.uuid as String)!,
                                              major: Int(beacon.major),
                                              minor: Int(beacon.minor),
                                              proximity: Int(beacon.proximity),
                                              accuracy: beacon.accuracy,
                                              rssi: Int(beacon.rssi),
                                              timestamp: beacon.timeIntervalSinceBootTime)
            }
        }
    }
    
    func processEddystoneBeaconTable() {
        
        countEddystoneBeacons()
        
        guard let beaconsUnwrapped = getAllEddystoneBeaconsAndDelete() else {
            return
        }
        
        Log.debug("\(beaconsUnwrapped.count) fetched from Eddystone beacons table")
        
        // create a key / value list that creates a unquiqe key for each beacon.
        var newBeacons: [[String:EddystoneBeacon]] = []
        
        for beacon in beaconsUnwrapped {
            
            var newBeacon: [String:EddystoneBeacon] = [:]
            
            newBeacon["\(beacon.eid)"] = beacon
            
            newBeacons.append(newBeacon)
        }
        
        // group all identical beacons under the unique key
        let groupedBeacons = newBeacons.group(by: {$0.keys.first!})
        
        var youngestBeaconInWindow: EddystoneBeacon?
        var beaconsPerWindow : [EddystoneBeacon] = []
        
        for beaconGroup in groupedBeacons {
            
            let sortedBeaconGroup = beaconGroup.value.sorted(by: {
                
                let value1 = $0.first!.value
                let value2 = $1.first!.value
                
                return value1.timeIntervalSinceBootTime < value2.timeIntervalSinceBootTime
            })
            
            youngestBeaconInWindow = sortedBeaconGroup[0].values.first
            
            beaconsPerWindow.append(youngestBeaconInWindow!)
            Log.verbose("Youngest beacon in window: \(String(describing: youngestBeaconInWindow))")
        }
        
        if let maxObservations = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterMaxObservations {
            
            var sortedValues = beaconsPerWindow.sorted(by: {$0.rssi > $1.rssi})
            
            if (sortedValues.count > Int(maxObservations)) {
                sortedValues = Array(sortedValues.prefix(Int(maxObservations)))
            }
            
            for beacon in sortedValues {
                delegate?.receivedEddystoneBeaconInfo(eid: beacon.eid, tx: Int(beacon.tx), rssi: Int(beacon.rssi), timestamp: beacon.timeIntervalSinceBootTime)
            }
        }
    }
}
