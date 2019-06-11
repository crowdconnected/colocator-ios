//
//  CCLocationManager.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 23/07/2017.
//  Copyright © 2017 Crowd Connected. All rights reserved.
//

import Foundation
import CoreLocation
//import os.log
//import UserNotifications
import SQLite3
import ReSwift
import CoreBluetooth // only needed to get bluetooth state, not needed for ibeacon locations

@objc protocol CCLocationManagerDelegate: class {
    func receivedGEOLocation(location: CLLocation)
    func receivediBeaconInfo(proximityUUID:UUID, major:Int, minor:Int, proximity:Int, accuracy:Double, rssi:Int, timestamp: TimeInterval)
    func receivedEddystoneBeaconInfo(eid:NSString, tx:Int, rssi:Int, timestamp:TimeInterval)
}

class CCLocationManager: NSObject, CLLocationManagerDelegate {
    
    internal let locationManager = CLLocationManager()
    internal let eddystoneBeaconScanner = BeaconScanner()
    
    internal var currentGEOState: CurrentGEOState!
    internal var currentBeaconState: CurrentBeaconState!
    internal var currentiBeaconMonitoringState: CurrentiBeaconMonitoringState!
    internal var wakeupState: WakeupState!
    
    internal var maxRunGEOTimer: Timer?
    internal var maxBeaconRunTimer: Timer?
    internal var minOffTimeBeaconTimer: Timer?
    internal var beaconWindowSizeDurationTimer: Timer?
    
    internal var centralManager:CBCentralManager!
    
    internal var iBeaconMessagesDB: SQLiteDatabase!
    internal let iBeaconMessagesDBName = "iBeaconMessages.db"
    
    internal var eddystoneBeaconMessagesDB: SQLiteDatabase!
    internal let eddystoneBeaconMessagesDBName = "eddystoneMessages.db"
    
    public weak var delegate:CCLocationManagerDelegate?
    
    weak var stateStore: Store<LibraryState>!
    
    public init(stateStore: Store<LibraryState>) {
        super.init()
        
        self.stateStore = stateStore
        
        currentGEOState = CurrentGEOState(isInForeground: nil, activityType: nil, maxRuntime: nil, minOffTime: nil, desiredAccuracy: nil, distanceFilter: nil, pausesUpdates: nil, isSignificantUpdates: nil, isStandardGEOEnabled: nil)
        
        currentiBeaconMonitoringState = CurrentiBeaconMonitoringState(monitoringRegions: [])
        
        currentBeaconState = CurrentBeaconState(isIBeaconEnabled: nil, isInForeground: nil, maxRuntime: nil, minOffTime: nil, regions: [], filterWindowSize: nil, filterMaxObservations: nil, filterExcludeRegions: [], offTime: nil, maxOnTimeStart: nil, eddystoneScanEnabled: false)
        
        wakeupState = WakeupState(ccWakeup: CCWakeup.idle)
        
        locationManager.delegate = self
        
        //        if #available(iOS 10.0, *) {
        //            UNUserNotificationCenter.current().delegate = self
        //        } else {
        //            // Fallback on earlier versions
        //        }
        
        stateStore.subscribe(self)
        {
            $0.select {
                state in state.locationSettingsState.currentLocationState!
            }
        }
        
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey:false])
        
        eddystoneBeaconScanner.delegate = self
        
        //initial dispatch of location state
        
        DispatchQueue.main.async {stateStore.dispatch(LocationAuthStatusChangedAction(locationAuthStatus: CLLocationManager.authorizationStatus()))}
        DispatchQueue.main.async {stateStore.dispatch(IsLocationServicesEnabledAction(isLocationServicesEnabled: CLLocationManager.locationServicesEnabled()))}
        
        openIBeaconDatabase()
        createIBeaconTable()
        
        openEddystoneBeaconDatabase()
        createEddystoneBeaconTable()
    }
    
    @objc func updateMonitoringForRegions () {
        
        // stop monitoring for regions
        self.stopMonitoringForBeaconRegions()
        
        // then see if we can start monitoring for new region
        
        //        DDLogVerbose("------- a list of monitored regions before adding iBeacons -------")
        //        for monitoredRegion in locationManager.monitoredRegions {
        //            DDLogVerbose("region \(monitoredRegion)")
        //        }
        //        DDLogVerbose("------- list end -------")
        
        for region in currentiBeaconMonitoringState.monitoringRegions {
            
            var regionInMonitoredRegions = false
            
            for monitoredRegion in locationManager.monitoredRegions {
                if monitoredRegion is CLBeaconRegion {
                    
                    if (monitoredRegion as! CLBeaconRegion).proximityUUID.uuidString == region.proximityUUID.uuidString {
                        regionInMonitoredRegions = true
                    }
                }
            }
            
            if (!regionInMonitoredRegions){
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
            if $0 is CLBeaconRegion {
                return (($0 as! CLBeaconRegion).identifier.range(of: "CC") != nil)
            }
            return false
        }
        
        // second stop monitoring for beacons that are not included in the current settings
        for region in crowdConnectedRegions {
            if !currentiBeaconMonitoringState.monitoringRegions.contains(region as! CLBeaconRegion){
                locationManager.stopMonitoring(for: region as! CLBeaconRegion)
            }
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
                eddystoneBeaconScanner.startScanning()
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
            maxBeaconRunTimer = Timer.scheduledTimer(timeInterval: TimeInterval(maxRuntime / 1000), target: self, selector: #selector(self.stopRangingBeaconsFor), userInfo: nil, repeats: false)
        }
    }
    
    func updateRangingIBeacons() {
        
        Log.debug("updateRangingIBeacons");
        
        // first stop ranging for any CrowdConnected regions
        stopRangingiBeacons(forCurrentSettings: true)
        
        // Then see if we can start ranging for new region
        for region in currentBeaconState.regions {
            
            var regionInRangedRegions = false
            
            for rangedRegion in locationManager.rangedRegions{
                if rangedRegion is CLBeaconRegion {
                    
                    if (rangedRegion as! CLBeaconRegion).proximityUUID.uuidString == region.proximityUUID.uuidString {
                        regionInRangedRegions = true
                    }
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
        eddystoneBeaconScanner.stopScanning()
        
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
                minOffTimeBeaconTimer = Timer.scheduledTimer(timeInterval: TimeInterval(minOffTime / 1000), target: self, selector: #selector(startBeaconScanning), userInfo: nil, repeats: false)
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
            if $0 is CLBeaconRegion {
                return (($0 as! CLBeaconRegion).identifier.range(of: "CC") != nil)
            }
            return false
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
    
    
    func startReceivingSignificantLocationChanges() {
        //        let authorizationStatus = CLLocationManager.authorizationStatus()
        //        if authorizationStatus != .authorizedAlways {
        //            // User has not authorized access to location information.
        //            return
        //        }
        //
        //        if !CLLocationManager.significantLocationChangeMonitoringAvailable() {
        //            // The service is not available.
        //            return
        //        }
        
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    func stopReceivingSignificantLocationChanges() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
    }
    
    @objc func stopLocationUpdates () {
        locationManager.stopUpdatingLocation()
        
        if (maxRunGEOTimer != nil) {
            maxRunGEOTimer?.invalidate()
            maxRunGEOTimer = nil
        }
        
        if let minOffTime = currentGEOState.minOffTime {
            
            if minOffTime > 0 {
                
                let offTimeEnd = Date().addingTimeInterval(TimeInterval(minOffTime / 1000))
                
                DispatchQueue.main.async {self.stateStore.dispatch(SetGEOOffTimeEnd(offTimeEnd: offTimeEnd))}
            } else {
                DispatchQueue.main.async {self.stateStore.dispatch(SetGEOOffTimeEnd(offTimeEnd: nil))}
            }
        }
    }
    
    func stopTimers () {
        
        if maxRunGEOTimer != nil {
            maxRunGEOTimer?.invalidate()
            maxRunGEOTimer = nil
        }
        
        if maxBeaconRunTimer != nil {
            maxBeaconRunTimer?.invalidate()
            maxBeaconRunTimer = nil
        }
        
        if minOffTimeBeaconTimer != nil {
            minOffTimeBeaconTimer?.invalidate()
            minOffTimeBeaconTimer = nil
        }
        
        if beaconWindowSizeDurationTimer != nil {
            beaconWindowSizeDurationTimer?.invalidate()
            beaconWindowSizeDurationTimer = nil
        }
    }
    
    public func stopAllLocationObservations () {

        locationManager.stopUpdatingLocation()
        stopReceivingSignificantLocationChanges()
        stopRangingiBeacons(forCurrentSettings: false)
        stopMonitoringForBeaconRegions()
        locationManager.delegate = nil
        centralManager.delegate = nil
        centralManager = nil
    }
    
    public func stop () {
        stopTimers()
        
        iBeaconMessagesDB.close()
        eddystoneBeaconMessagesDB.close()
        
        iBeaconMessagesDB = nil
        eddystoneBeaconMessagesDB = nil
        
        stateStore.unsubscribe(self)
        stopAllLocationObservations()
    }
    
    // MARK:- iBeacon database handling
    
    func openIBeaconDatabase() {
        // Get the library directory
        let dirPaths = NSSearchPathForDirectoriesInDomains (.libraryDirectory, .userDomainMask, true)
        
        let docsDir = dirPaths[0]
        
        // Build the path to the database file
        let beaconDBPath = URL.init(string: docsDir)?.appendingPathComponent(iBeaconMessagesDBName).absoluteString
        
        guard let beaconDBPathStringUnwrapped = beaconDBPath else {
            Log.error("Unable to create beacon database path")
            return
        }
        
        do {
            iBeaconMessagesDB = try SQLiteDatabase.open(path: beaconDBPathStringUnwrapped)
            Log.debug("Successfully opened connection to beacon database.")
        } catch SQLiteError.OpenDatabase(let message) {
            Log.error("Unable to open database. \(message)")
        } catch {
            Log.error("An unexpected error was thrown, when trying to open a connection to beacon database")
        }
    }
    
    
    func createIBeaconTable() {
        
        do {
            try iBeaconMessagesDB.createTable(table: Beacon.self)
        } catch {
            Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
        }
    }
    
    func insert(beacon: CLBeacon) {
        
        if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
            
            do {
                try iBeaconMessagesDB.insertBeacon(beacon: Beacon (
                    uuid: beacon.proximityUUID.uuidString as NSString,
                    major: beacon.major.int32Value,
                    minor: beacon.minor.int32Value,
                    proximity: Int32(beacon.proximity.rawValue),
                    accuracy: beacon.accuracy,
                    rssi: Int32(beacon.rssi),
                    timeIntervalSinceBootTime: timeIntervalSinceBoot
                ))
            } catch {
                Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
            }
        }
    }
    
    @objc func processBeaconTables() {
        processiBeaconTable()
        processEddystoneBeaconTable()
    }
    
    func processiBeaconTable() {
        
        do {
            let beaconCount = try iBeaconMessagesDB.count(table:CCLocationTables.IBEACON_MESSAGES_TABLE)
            Log.debug("Process beacon table, beacon count: \(String(describing: beaconCount))")
        } catch {
            Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
        }
        
        var beacons:[Beacon]?
        
        do {
            try beacons = iBeaconMessagesDB.allBeaconsAndDelete()
        } catch {
            Log.error("Beacon database error: \(iBeaconMessagesDB.errorMessage)")
        }
        
        guard let beaconsUnwrapped = beacons else {
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
    
    // MARK:- Eddystone Beacon database handling
    
    func openEddystoneBeaconDatabase() {
        // Get the library directory
        let dirPaths = NSSearchPathForDirectoriesInDomains (.libraryDirectory, .userDomainMask, true)
        
        let docsDir = dirPaths[0]
        
        // Build the path to the database file
        let beaconDBPath = URL.init(string: docsDir)?.appendingPathComponent(eddystoneBeaconMessagesDBName).absoluteString
        
        guard let beaconDBPathStringUnwrapped = beaconDBPath else {
            Log.error("Unable to create beacon database path")
            return
        }
        
        do {
            eddystoneBeaconMessagesDB = try SQLiteDatabase.open(path: beaconDBPathStringUnwrapped)
            Log.debug("Successfully opened connection to Eddystone database.")
        } catch SQLiteError.OpenDatabase(let message) {
            Log.error("Unable to open database. \(message)")
        } catch {
            Log.error("An unexpected error was thrown, when trying to open a connection to Eddystone database")
        }
    }
    
    func createEddystoneBeaconTable() {
        
        do {
            try eddystoneBeaconMessagesDB.createTable(table: EddystoneBeacon.self)
        } catch {
            Log.error("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
        }
    }
    
    func insert(eddystoneBeacon: EddystoneBeaconInfo) {
        if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
            
            do {
                try eddystoneBeaconMessagesDB.insertEddystoneBeacon(eddystoneBeacon: EddystoneBeacon (
                    eid: eddystoneBeacon.beaconID.hexBeaconID() as NSString,
                    rssi: Int32(eddystoneBeacon.RSSI),
                    tx: Int32(eddystoneBeacon.txPower),
                    timeIntervalSinceBootTime: timeIntervalSinceBoot
                ))
            } catch {
                Log.error("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
            }
        }
    }
    
    func processEddystoneBeaconTable() {
        
        do {
            let beaconCount = try eddystoneBeaconMessagesDB.count(table:CCLocationTables.EDDYSTONE_BEACON_MESSAGES_TABLE)
            Log.debug("Process Eddystone beacon table, beacon count: \(String(describing: beaconCount))")
        } catch {
            Log.debug("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
        }
        
        var beacons:[EddystoneBeacon]?
        
        do {
            try beacons = eddystoneBeaconMessagesDB.allEddystoneBeaconsAndDelete()
            
        } catch {
            Log.error("Eddystone beacon database error: \(eddystoneBeaconMessagesDB.errorMessage)")
        }
        
        guard let beaconsUnwrapped = beacons else {
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


// MARK:- Responding to Location Events
extension CCLocationManager {
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        //Log.debug("Received \(locations.count) locations")
        
        for location in locations {
            Log.debug("geolocation information: \(location.description)")
            
            //            if #available(iOS 10.0, *) {
            //                let content = UNMutableNotificationContent()
            //                content.title = "GEO location event"
            //                content.body = "\(location.description)"
            //                content.sound = .default()
            //
            //                let request = UNNotificationRequest(identifier: "GEOLocation", content: content, trigger: nil)
            //                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
            //
            //                os_log("[CC] A geolocation was discovered")
            //            }
            
            delegate?.receivedGEOLocation(location: location)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        switch (error) {
        case CLError.headingFailure:
            //Log.error(String(format:"locationManager didFailWithError kCLErrorHeadingFailure occured with description: %@", error.localizedDescription));
            break
            
        // as per Apple documentation, locationUnknown error occures when the location service is unable to retrieve a location right away, but keeps trying, simply to ignore and wait for new event
        case CLError.locationUnknown:
            //Log.error(String(format:"locationManager didFailWithError kCLErrorLocationUnknown occured with description: %@", error.localizedDescription));
            break
            
        // as per Apple documentation, denied error occures when the user denies location services, if that happens we should stop location services
        case CLError.denied:
            //Log.error(String(format:"locationManager didFailWithError kCLErrorDenied occured with description: %@", error.localizedDescription));
            
            // According to API reference on denied error occures, when users stops location services, so we should stop them as well here
            
            // TODO: wrap into stop function to stop everything
            //            self.locationManager.stopUpdatingLocation()
            //            self.locationManager.stopMonitoringSignificantLocationChanges()
            break
            
        default:
            //Log.error(String(format:"locationManager didFailWithError Unknown location error occured with description: %@", error.localizedDescription));
            break
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        //        guard let error = error else {
        //            return
        //        }
        
        //Log.error(error.localizedDescription)
    }
}

// MARK: - Responding to Eddystone Beacon Discovery Events
extension CCLocationManager: BeaconScannerDelegate {
    func didFindBeacon(beaconScanner: BeaconScanner, beaconInfo: EddystoneBeaconInfo) {
        Log.verbose("FIND: \(beaconInfo.description)")
        
        if (beaconInfo.beaconID.beaconType == BeaconID.BeaconType.EddystoneEID){
            
            var isFilterAvailable = false
            
            // check if windowSize and maxObservations are available
            if let windowSize = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterWindowSize {
                if let maxObservations = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterMaxObservations {
                    if windowSize > 0 && maxObservations > 0 {
                        isFilterAvailable = true
                    }
                }
            }
            
            if isFilterAvailable {
                insert(eddystoneBeacon: beaconInfo)
            } else {
                if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                    delegate?.receivedEddystoneBeaconInfo(
                        eid: beaconInfo.beaconID.hexBeaconID() as NSString,
                        tx: beaconInfo.txPower,
                        rssi: beaconInfo.RSSI,
                        timestamp: timeIntervalSinceBoot
                    )
                }
            }
            
        }
    }
    
    func didLoseBeacon(beaconScanner: BeaconScanner, beaconInfo: EddystoneBeaconInfo) {
        Log.verbose("LOST: \(beaconInfo.description)")
    }
    
    func didUpdateBeacon(beaconScanner: BeaconScanner, beaconInfo: EddystoneBeaconInfo) {
        Log.verbose("UPDATE: \(beaconInfo.description)")
        
        if (beaconInfo.beaconID.beaconType == BeaconID.BeaconType.EddystoneEID){
            
            var isFilterAvailable = false
            
            // check if windowSize and maxObservations are available
            if let windowSize = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterWindowSize {
                if let maxObservations = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterMaxObservations {
                    if windowSize > 0 && maxObservations > 0 {
                        isFilterAvailable = true
                    }
                }
            }
            
            if isFilterAvailable {
                insert(eddystoneBeacon: beaconInfo)
            } else {
                if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                    delegate?.receivedEddystoneBeaconInfo(
                        eid: beaconInfo.beaconID.hexBeaconID() as NSString,
                        tx: beaconInfo.txPower,
                        rssi: beaconInfo.RSSI,
                        timestamp: timeIntervalSinceBoot
                    )
                }
            }
        }
    }
    
    func didObserveURLBeacon(beaconScanner: BeaconScanner, URL: NSURL, RSSI: Int) {
        Log.verbose("URL SEEN: \(URL), RSSI: \(RSSI)")
    }
}


// MARK: - Responding to Region Events
extension CCLocationManager {
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region is CLBeaconRegion else {
            return
        }
        
        DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.idle))}
        DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.notifyWakeup))}
        
        //        if #available(iOS 10.0, *) {
        //            let content = UNMutableNotificationContent()
        //            content.title = "Region entry event"
        //            content.body = "You entered a beacon region"
        //            content.sound = .default()
        //
        //            let request = UNNotificationRequest(identifier: "didEnterRegion", content: content, trigger: nil)
        //            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        //
        //            let localNotification = UILocalNotification()
        //            localNotification.soundName = UILocalNotificationDefaultSoundName
        //            UIApplication.shared.scheduleLocalNotification(localNotification)
        //
        //            Log.debug("[CC] You entered a beacon region")
        //        } else {
        //            // Fallback on earlier versions
        //        }
        
        
    }
    
    
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region is CLBeaconRegion else {
            return
        }
        
        DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.idle))}
        DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.notifyWakeup))}
        
        //        if #available(iOS 10.0, *) {
        //            let content = UNMutableNotificationContent()
        //            content.title = "Region exit event"
        //            content.body = "You left a beacon region"
        //            content.sound = .default()
        //
        //            let request = UNNotificationRequest(identifier: "didExitRegion", content: content, trigger: nil)
        //            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        //
        //            let localNotification = UILocalNotification()
        //            localNotification.soundName = UILocalNotificationDefaultSoundName
        //            UIApplication.shared.scheduleLocalNotification(localNotification)
        //
        //            Log.debug("[CC] You left a beacon region")
        //        } else {
        //            // Fallback on earlier versions
        //        }
        
        
    }
    
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        //        switch state {
        //        case .inside:
        //            Log.verbose(String(format: "Inside region: %@", region.identifier))
        //        case .outside:
        //            Log.verbose(String(format: "Outside region: %@", region.identifier))
        //        case .unknown:
        //            Log.verbose(String(format: "Unkown region state: %@", region.identifier))
        //        }
    }
    
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        
        guard let region = region else {
            return
        }
        
        Log.error(String(format:"Monitoring did fail for Region: %@", region.identifier))
    }
    
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion){
        //        if let beaconRegion = region as? CLBeaconRegion {
        //            Log.debug("Did start monitoring for region: \(beaconRegion.identifier) uuid: \(beaconRegion.proximityUUID) major: \(String(describing: beaconRegion.major)) minor: \(String(describing: beaconRegion.minor))")
        //
        //            Log.verbose("------- a list of monitored regions -------")
        //            for monitoredRegion in locationManager.monitoredRegions {
        //                DDLogVerbose("\(monitoredRegion)")
        //            }
        //            Log.verbose("------- list end -------")
        //
        //        }
    }
}

// MARK: - Responding to Ranging Events
extension CCLocationManager {
    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        if (beacons.count > 0){
            for beacon in beacons {
                
//                Log.verbose("Ranged beacon with UUID: \(beacon.proximityUUID.uuidString), MAJOR: \(beacon.major), MINOR: \(beacon.minor), RSSI: \(beacon.rssi)")
                
                
                //                if #available(iOS 10.0, *) {
                //                    let content = UNMutableNotificationContent()
                //                    content.title = "iBeacon ranged"
                //                    content.body = "UUID: \(beacon.proximityUUID.uuidString), MAJ: \(beacon.major), MIN: \(beacon.minor), RSSI: \(beacon.rssi)"
                //                    content.sound = .default()
                //
                //                    let request = UNNotificationRequest(identifier: "GEOLocation", content: content, trigger: nil)
                //                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                //
                //                    os_log("[CC] A beacon was ranged")
                //                }
                
                // mainly excluding RSSI's that are zero, which happens some time
                if beacon.rssi < 0 {
                    
                    var isFilterAvailable:Bool = false
                    
                    // check if windowSize and maxObservations are available
                    if let windowSize = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterWindowSize {
                        if let maxObservations = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterMaxObservations {
                            if windowSize > 0 && maxObservations > 0 {
                                isFilterAvailable = true
                            }
                        }
                    }
                    
                    // check if exclude regions
                    if let excludeRegions = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterExcludeRegions{
                        let results = Array(excludeRegions.filter { region in
                            
                            if region.proximityUUID.uuidString == beacon.proximityUUID.uuidString {
                                
                                if let major = region.major {
                                    if major == beacon.major {
                                        
                                        if let minor = region.minor {
                                            if minor == beacon.minor {
                                                return true
                                            }
                                        } else {
                                            return true
                                        }
                                    }
                                } else {
                                    return true
                                }
                            }
                            return false
                        })
                        
                        if results.count > 0 {
                            Log.debug("Beacon is in exclude regions")
                        } else {
//                            Log.debug("Beacon is input to reporting")
                            
                            if isFilterAvailable {
                                insert(beacon: beacon)
                            } else {
                                if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                                    delegate?.receivediBeaconInfo(proximityUUID: beacon.proximityUUID, major: Int(truncating: beacon.major), minor: Int(truncating: beacon.minor), proximity: beacon.proximity.rawValue, accuracy: beacon.accuracy, rssi: Int(beacon.rssi), timestamp: timeIntervalSinceBoot)
                                }
                            }
                        }
                    }
                    else {
                        if isFilterAvailable {
                            insert(beacon: beacon)
                        } else {
                            if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                                delegate?.receivediBeaconInfo(proximityUUID: beacon.proximityUUID, major: Int(truncating: beacon.major), minor: Int(truncating: beacon.minor), proximity: beacon.proximity.rawValue, accuracy: beacon.accuracy, rssi: Int(beacon.rssi), timestamp: timeIntervalSinceBoot)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        Log.error("Ranging failed for region with UUID: \(region.proximityUUID.uuidString)")
    }
}


// MARK: - Responding to Authorization Changes
extension CCLocationManager {
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Log.debug("Changed authorization status")
        
        DispatchQueue.main.async {self.stateStore.dispatch(LocationAuthStatusChangedAction(locationAuthStatus: status))}
        DispatchQueue.main.async {self.stateStore.dispatch(IsLocationServicesEnabledAction(isLocationServicesEnabled: CLLocationManager.locationServicesEnabled()))}
        
        switch (status) {
        case .notDetermined:
            // Log.debug("CLLocationManager authorization status not determined")
            break
            
        case .restricted:
            // Log.verbose("CLLocationManager authorization status restricted, can not use location services")
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
            
            break
            
        case .denied:
            //            DDLogVerbose("CLLocationManager authorization status denied in user settings, can not use location services, until user enables them")
            // might consider here to ask a question to the user to enable location services again
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
            
            break
            
        case .authorizedAlways:
//            Log.verbose("CLLocationManager authorization status set to always authorized, we are ready to go")
            
            if #available(iOS 9.0, *) {
                //                if #available(iOS 10.0, *) {
                //                    os_log("[CC] Enabling allowsBackgroundLocationUpdates")
                //                } else {
                //                    // Fallback on earlier versions
                //                }
                locationManager.allowsBackgroundLocationUpdates = true
            } else {
                // Fallback on earlier versions
            }
            
            break
            
        case .authorizedWhenInUse:
            //            Log.verbose("CLLocationManager authorization status set to in use, no background updates enabled")
            // might need to consider here to ask a question to the user to enable background location services
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
            
            break
        }
    }
}

// MARK: - Responding to state changes
extension CCLocationManager: StoreSubscriber {
    public func newState(state: CurrentLocationState) {
        
        if let newGEOState = state.currentGEOState {
            
            let wakeupState = stateStore.state.locationSettingsState.currentLocationState?.wakeupState?.ccWakeup
            
            if newGEOState != self.currentGEOState || wakeupState == CCWakeup.notifyWakeup {
                
//                Log.debug("new state is: \(newGEOState)")
                
                self.currentGEOState = newGEOState
                
                if let isSignificantUpdates = newGEOState.isSignificantLocationChangeMonitoringState {
                    if isSignificantUpdates {
                        startReceivingSignificantLocationChanges()
                    } else {
                        stopReceivingSignificantLocationChanges()
                    }
                }
                
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
                                //Log.verbose("GEOTIMER offTime \(offTime) occured before current time \(Date()), resetting offTime")
                                DispatchQueue.main.async {self.stateStore.dispatch(SetGEOOffTimeEnd(offTimeEnd: nil))}
                            } else {
                                //Log.verbose("GEOTIMER offTime \(offTime) occured after current date \(Date()), keeping offTime and doing nothing")
                                // do nothing
                            }
                            // and in case there is not offTime, just start the location manager for maxRuntime
                        } else {
                            //Log.verbose("GEOTIMER startUpdatingLocation no offTime available")
                            locationManager.startUpdatingLocation()
                            
                            // Log.verbose("Enabled GEO settings are activityType:\(locationManager.activityType), desiredAccuracy: \(locationManager.desiredAccuracy), distanceFilter: \(locationManager.distanceFilter), pausesUpdates: \(locationManager.pausesLocationUpdatesAutomatically)")
                            
                            if let maxRunTime = newGEOState.maxRuntime {
                                if (self.maxRunGEOTimer == nil){
                                    //Log.verbose("GEOTIMER start maxGEORunTimer \(maxRunTime)")
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
        }
        
        if let newiBeaconMonitoringState = state.currentiBeaconMonitoringState{
            
            if newiBeaconMonitoringState != self.currentiBeaconMonitoringState{
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
                    //                                    //                                        DDLogVerbose("IBEACONTIMER start maxRunTimer \(maxRuntime)")
                    //                                    maxBeaconRunTimer = Timer.scheduledTimer(timeInterval: TimeInterval(maxRuntime / 1000), target: self, selector: #selector(stopRangingBeaconsFor), userInfo: nil, repeats: false)
                    //                                    stateStore.dispatch(SetiBEaconMaxOnTimeStartAction(maxOnTimeStart: Date()))
                    //                                }
                    //                            }
                    //                        }
                    
                    // manage timer for beacon window size duration
                    
                    if let beaconWindowSizeDuration = currentBeaconState.filterWindowSize {
                        // initialise time on filterWindowSize being available
                        if beaconWindowSizeDurationTimer == nil {
//                            Log.verbose("BEACONWINDOWSIZETIMER start beaconWindowSizeDuration timer with: \(beaconWindowSizeDuration)")
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
            //DDLogDebug("got a wake up state reported, state is: \(newWakeupNotificationState)")
            if newWakeupNotificationState != wakeupState {
                wakeupState = newWakeupNotificationState
                //DDLogDebug("new state is: \(newWakeupNotificationState)")
                if wakeupState.ccWakeup == CCWakeup.notifyWakeup{
                    DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.idle))}
                }
            }
        }
    }
}

//@available(iOS 10.0, *)
//extension CCLocationManager:UNUserNotificationCenterDelegate{
//
//    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
//
//        print("Tapped in notification")
//    }
//
//    //This is key callback to present notification while the app is in foreground
//    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
//
//        print("Notification being triggered")
//        //You can either present alert ,sound or increase badge while the app is in foreground too with ios 10
//        //to distinguish between notifications
//
//            completionHandler( [.alert, .sound,.badge])
//
//    }
//}

extension CCLocationManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {self.stateStore.dispatch(BluetoothHardwareChangedAction(bluetoothHardware: central.centralManagerState))}
    }
}

extension CBCentralManager {
    internal var centralManagerState: CBCentralManagerState {
        get {
            return CBCentralManagerState(rawValue: state.rawValue) ?? .unknown
        }
    }
}
