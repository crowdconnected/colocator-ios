//
//  CCLocationManager.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 23/07/2017.
//  Copyright © 2017 Crowd Connected. All rights reserved.
//

import Foundation
import CoreLocation
import SQLite3
import ReSwift
import CoreBluetooth

enum GeofenceEventType: Int {
    case enter = 1
    case exit = 2
}

@objc protocol CCLocationManagerDelegate: class {
    func receivedGEOLocation(location: CLLocation)
    func receivedGeofenceEvent(type: Int, region: CLCircularRegion)
    func receivediBeaconInfo(proximityUUID:UUID, major:Int, minor:Int, proximity:Int, accuracy:Double, rssi:Int, timestamp: TimeInterval)
    func receivedEddystoneBeaconInfo(eid:NSString, tx:Int, rssi:Int, timestamp:TimeInterval)
}

class CCLocationManager: NSObject, CLLocationManagerDelegate {
    
    internal let locationManager = CLLocationManager()
    internal var eddystoneBeaconScanner: BeaconScanner? = nil
    
    internal var currentGEOState: CurrentGEOState!
    internal var currentGeofencesMonitoringState: CurrentGeofencesMonitoringState!
    internal var currentBeaconState: CurrentBeaconState!
    internal var currentiBeaconMonitoringState: CurrentiBeaconMonitoringState!
    internal var wakeupState: WakeupState!
    
    internal var maxRunGEOTimer: Timer?
    internal var maxBeaconRunTimer: Timer?
    internal var minOffTimeBeaconTimer: Timer?
    internal var beaconWindowSizeDurationTimer: Timer?
    
    internal var centralManager: CBCentralManager?
    
    internal var iBeaconMessagesDB: SQLiteDatabase!
    internal let iBeaconMessagesDBName = "iBeaconMessages.db"
    
    internal var eddystoneBeaconMessagesDB: SQLiteDatabase!
    internal let eddystoneBeaconMessagesDBName = "eddystoneMessages.db"
    
    public weak var delegate: CCLocationManagerDelegate?
    
    weak var stateStore: Store<LibraryState>!
    
    // Initial value has to be true, otherwise after force quiting the app, the location manager will never start collecting all the data again
    var isWaitingForSignificantUpdates = true
    
    var isContinuousGEOCollectionActive = true
    
    public init(stateStore: Store<LibraryState>) {
        super.init()
        
        self.stateStore = stateStore
        
        currentGEOState = CurrentGEOState(isInForeground: nil,
                                          activityType: nil,
                                          maxRuntime: nil,
                                          minOffTime: nil,
                                          desiredAccuracy: nil,
                                          distanceFilter: nil,
                                          pausesUpdates: nil,
                                          isSignificantUpdates: nil,
                                          isStandardGEOEnabled: nil)
        
        currentGeofencesMonitoringState = CurrentGeofencesMonitoringState(monitoringGeofences: [])
        currentiBeaconMonitoringState = CurrentiBeaconMonitoringState(monitoringRegions: [])
        
        currentBeaconState = CurrentBeaconState(isIBeaconEnabled: nil,
                                                isInForeground: nil,
                                                maxRuntime: nil,
                                                minOffTime: nil,
                                                regions: [],
                                                filterWindowSize: nil,
                                                filterMaxObservations: nil,
                                                filterExcludeRegions: [],
                                                offTime: nil,
                                                maxOnTimeStart: nil,
                                                eddystoneScanEnabled: false)
        
        wakeupState = WakeupState(ccWakeup: CCWakeup.idle)
        
        locationManager.delegate = self
        
        stateStore.subscribe(self)
        {
            $0.select {
                state in state.locationSettingsState.currentLocationState!
            }
        }
        
        centralManager = CBCentralManager(delegate: self,
                                          queue: nil,
                                          options: [CBCentralManagerOptionShowPowerAlertKey:false])
        
        eddystoneBeaconScanner = BeaconScanner()
        eddystoneBeaconScanner?.delegate = self
        
        // initial dispatch of location state
        DispatchQueue.main.async {stateStore.dispatch(LocationAuthStatusChangedAction(locationAuthStatus: CLLocationManager.authorizationStatus()))}
        DispatchQueue.main.async {stateStore.dispatch(IsLocationServicesEnabledAction(isLocationServicesEnabled: CLLocationManager.locationServicesEnabled()))}
        
        openIBeaconDatabase()
        createIBeaconTable()
        
        openEddystoneBeaconDatabase()
        createEddystoneBeaconTable()
    }
    
    func startReceivingSignificantLocationChanges() {
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    func stopReceivingSignificantLocationChanges() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
    }
    
    @objc func stopLocationUpdates() {
        Log.info("Stop collecting GEO")
        
        locationManager.stopUpdatingLocation()
        
        Log.debug("Waiting for significant updates only")
        
        isWaitingForSignificantUpdates = true
        isContinuousGEOCollectionActive = false
        
        if maxRunGEOTimer != nil {
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
    
    func updateMonitoringGeofences() {
        stopMonitoringRemovedGeofences()
        
        Log.debug("\nUpdate monitored geofences\n\n")
        
        Log.verbose("------- List of monitored geofences before adding new ones -------")
        for monitoredGeofence in locationManager.monitoredRegions {
            Log.verbose("Geofence \(monitoredGeofence)")
        }
        Log.verbose("------- List end -------")
        
        for geofence in currentGeofencesMonitoringState.monitoringGeofences {
            var geofenceInMonitoredRegions = false
            
            for monitoredGeofence in locationManager.monitoredRegions where monitoredGeofence is CLCircularRegion {
                if (monitoredGeofence as! CLCircularRegion).identifier == geofence.identifier {
                    geofenceInMonitoredRegions = true
                }
            }
            
            if !geofenceInMonitoredRegions &&
                CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
                
                geofence.notifyOnEntry = true
                geofence.notifyOnExit = true
                locationManager.startMonitoring(for: geofence)
            }
        }
    }
    
    func stopMonitoringRemovedGeofences() {
        Log.debug("\nStop monitoring previous geofences")
        
        let crowdConnectedGeofences = locationManager.monitoredRegions.filter {
            return $0 is CLCircularRegion ? (($0 as! CLCircularRegion).identifier.range(of: "CC") != nil) : false
        }
        
        for geofence in crowdConnectedGeofences
            where !currentGeofencesMonitoringState.monitoringGeofences.contains(geofence as! CLCircularRegion) {
            locationManager.stopMonitoring(for: geofence as! CLCircularRegion)
        }
    }
    
    func getCurrentGeofences() -> [CLCircularRegion] {
          var geofences = [CLCircularRegion]()
          
          for monitoredGeofence in locationManager.monitoredRegions where monitoredGeofence is CLCircularRegion {
              geofences.append(monitoredGeofence as! CLCircularRegion)
          }
          
          return geofences
      }
    
    func stopTimers() {
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
    }
    
    public func updateGEOAndBeaconStatesWithoutObservations() {
        currentGEOState.isStandardGEOEnabled = false
        currentGEOState.isSignificantLocationChangeMonitoringState = false
        saveCurrentGEOSateToUserDefaults(geoState: currentGEOState)
        
        currentBeaconState.isIBeaconRangingEnabled = false
        currentBeaconState.regions = []
        saveCurrentiBeaconStateToUserDefaults(currentiBeaconState: currentBeaconState)
    }
    
    private func removeLocationManagers() {
        locationManager.delegate = nil
        centralManager?.delegate = nil
        centralManager = nil
    }
    
    public func stop() {
        stopTimers()
        
        iBeaconMessagesDB.close()
        eddystoneBeaconMessagesDB.close()
        
        iBeaconMessagesDB = nil
        eddystoneBeaconMessagesDB = nil
        
        stateStore.unsubscribe(self)
        stopAllLocationObservations()
        removeLocationManagers()
    }
}

// MARK:- Responding to Location Events

extension CCLocationManager {
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Log.debug("Received \(locations.count) location(s)")
        
        for location in locations {
            Log.verbose("Geolocation information: \(location.description)")
            delegate?.receivedGEOLocation(location: location)
        }
        
        // Significant updates doesn't trigger a wake up state
        // If GEO data collection is not continuously, then check current state and update location manager behavior
        if isWaitingForSignificantUpdates {
            if isContinuousGEOCollectionActive == false {
                Log.verbose("Renew current GEO state at significant update")
                
                updateGEOState(currentGEOState)
                if isContinuousGEOCollectionActive {
                    isWaitingForSignificantUpdates = false
                }
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        switch (error) {
        case CLError.headingFailure:
            Log.error("LocationManager didFailWithError kCLErrorHeadingFailure: \(error.localizedDescription)")
            //LocationUnknown error occures when the location service is unable to retrieve a location right away, but keeps trying, simply to ignore and wait for new event
        case CLError.locationUnknown:
            Log.error("LocationManager didFailWithError kCLErrorLocationUnknown: \(error.localizedDescription)")
            //Denied error occures when the user denies location services, if that happens we should stop location services
        case CLError.denied:
            Log.error("LocationManager didFailWithError kCLErrorDenied: \(error.localizedDescription)")
            // According to API reference on denied error occures, when users stops location services, so we should stop them as well here
            
            // TODO: wrap into stop function to stop everything
            //            self.locationManager.stopUpdatingLocation()
            //            self.locationManager.stopMonitoringSignificantLocationChanges()
        default:
            Log.error("LocationManager didFailWithError Unknown: \(error.localizedDescription)")
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        Log.error("Did finish deferred updates with error \(error?.localizedDescription ?? "nil"))")
    }
}

// MARK: - Responding to Eddystone Beacon Discovery Events

extension CCLocationManager: BeaconScannerDelegate {
    func didFindBeacon(beaconScanner: BeaconScanner, beaconInfo: EddystoneBeaconInfo) {
        Log.verbose("Finde beacon \(beaconInfo.description)")
        
        if beaconInfo.beaconID.beaconType == BeaconID.BeaconType.EddystoneEID {
            var isFilterAvailable = false
            checkIfWindowSizeAndMaxObservationsAreAvailable(&isFilterAvailable)
            
            if isFilterAvailable {
                insert(eddystoneBeacon: beaconInfo)
            } else if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                delegate?.receivedEddystoneBeaconInfo(eid: beaconInfo.beaconID.hexBeaconID() as NSString,
                                                      tx: beaconInfo.txPower,
                                                      rssi: beaconInfo.RSSI,
                                                      timestamp: timeIntervalSinceBoot)
            }
        }
    }
    
    func didLoseBeacon(beaconScanner: BeaconScanner, beaconInfo: EddystoneBeaconInfo) {
        Log.verbose("Lost beacon \(beaconInfo.description)")
    }
    
    func didUpdateBeacon(beaconScanner: BeaconScanner, beaconInfo: EddystoneBeaconInfo) {
        Log.verbose("Update beacon \(beaconInfo.description)")
        
        if beaconInfo.beaconID.beaconType == BeaconID.BeaconType.EddystoneEID {
            var isFilterAvailable = false
            checkIfWindowSizeAndMaxObservationsAreAvailable(&isFilterAvailable)
            
            if isFilterAvailable {
                insert(eddystoneBeacon: beaconInfo)
            } else if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                delegate?.receivedEddystoneBeaconInfo(eid: beaconInfo.beaconID.hexBeaconID() as NSString,
                                                      tx: beaconInfo.txPower,
                                                      rssi: beaconInfo.RSSI,
                                                      timestamp: timeIntervalSinceBoot)
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
        let isBeaconRegion = region is CLBeaconRegion
        let isCCGeofence = region is CLCircularRegion && region.identifier.contains("CC")
        
        if isBeaconRegion || isCCGeofence {
            triggerWakeUpAction()
        }
        
        if isCCGeofence {
            Log.debug("User entered geofence with identifier: \(region.identifier)")
            delegate?.receivedGeofenceEvent(type: GeofenceEventType.enter.rawValue, region: region as! CLCircularRegion)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let isBeaconRegion = region is CLBeaconRegion
        let isCCGeofence = region is CLCircularRegion && region.identifier.contains("CC")
               
        if isBeaconRegion || isCCGeofence {
            triggerWakeUpAction()
        }
        
        if isCCGeofence {
            Log.debug("User exited geofence with identifier: \(region.identifier)")
            delegate?.receivedGeofenceEvent(type: GeofenceEventType.exit.rawValue, region: region as! CLCircularRegion)
        }
    }
    
    private func triggerWakeUpAction() {
        DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.idle))}
        DispatchQueue.main.async {self.stateStore.dispatch(NotifyWakeupAction(ccWakeup: CCWakeup.notifyWakeup))}
    }
    
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        switch state {
        case .inside:
            Log.verbose(String(format: "Inside region: %@", region.identifier))
        case .outside:
            Log.verbose(String(format: "Outside region: %@", region.identifier))
        case .unknown:
            Log.verbose(String(format: "Unkown region state: %@", region.identifier))
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let region = region else {
            return
        }
        
        Log.error(String(format:"Monitoring did fail for Region: %@", region.identifier))
    }
    
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        if let beaconRegion = region as? CLBeaconRegion {
            Log.verbose("""
                Did start monitoring for region \(beaconRegion.identifier)
                uuid: \(beaconRegion.proximityUUID)
                major: \(String(describing: beaconRegion.major))
                minor: \(String(describing: beaconRegion.minor))
                """)
        }
    }
}

// MARK: - Responding to Ranging Events

extension CCLocationManager {
    
    fileprivate func checkIfWindowSizeAndMaxObservationsAreAvailable(_ isFilterAvailable: inout Bool) {
        guard let currentBeaconState = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState else {
            return
        }
        
        if let windowSize = currentBeaconState.filterWindowSize,
            let maxObservations = currentBeaconState.filterMaxObservations {
            if windowSize > 0 && maxObservations > 0 {
                isFilterAvailable = true
            }
        }
    }
    
    fileprivate func checkRegionBelonging(_ region: CLBeaconRegion, beacon: CLBeacon) -> Bool {
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
    }
    
    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        guard !beacons.isEmpty else {
            return
        }
   
        for beacon in beacons where beacon.rssi < 0 {
            Log.verbose("""
                Ranged beacon with UUID \(beacon.proximityUUID.uuidString)
                MAJOR: \(beacon.major)
                MINOR: \(beacon.minor)
                RSSI: \(beacon.rssi)
                """)
            
            var isFilterAvailable: Bool = false
            checkIfWindowSizeAndMaxObservationsAreAvailable(&isFilterAvailable)
            
            let extractedCurrentBeaconState = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState
            
            if let excludeRegions = extractedCurrentBeaconState?.filterExcludeRegions {
                checkBeaconInExcludedRegions(beacon: beacon,
                                             excludedregions: excludeRegions,
                                             filter: isFilterAvailable)
            } else {
                if isFilterAvailable {
                    insert(beacon: beacon)
                } else {
                    sendBeaconInfoToDelegate(beacon)
                }
            }
        }
    }
    
    private func checkBeaconInExcludedRegions(beacon: CLBeacon, excludedregions: [CLBeaconRegion], filter: Bool) {
        let results = Array(excludedregions.filter { region in
            return checkRegionBelonging(region, beacon: beacon)
        })
       
        if results.count > 0 {
            Log.verbose("Beacon is in exclude regions")
        } else {
            Log.verbose("Beacon is input to reporting")
           
            if filter {
                insert(beacon: beacon)
            } else {
                sendBeaconInfoToDelegate(beacon)
            }
        }
    }
    
    private func sendBeaconInfoToDelegate(_ beacon: CLBeacon) {
        if let timeIntervalSinceBoot = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
            delegate?.receivediBeaconInfo(proximityUUID: beacon.proximityUUID,
                                          major: Int(truncating: beacon.major),
                                          minor: Int(truncating: beacon.minor),
                                          proximity: beacon.proximity.rawValue,
                                          accuracy: beacon.accuracy,
                                          rssi: Int(beacon.rssi),
                                          timestamp: timeIntervalSinceBoot)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        Log.error("Ranging failed for region with UUID: \(region.proximityUUID.uuidString)")
    }
}

// MARK: - Responding to Authorization Changes

extension CCLocationManager {
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Log.debug("Changed authorization status")
        
        DispatchQueue.main.async {self.stateStore.dispatch(LocationAuthStatusChangedAction(locationAuthStatus: status))}
        DispatchQueue.main.async {self.stateStore.dispatch(IsLocationServicesEnabledAction(isLocationServicesEnabled: CLLocationManager.locationServicesEnabled()))}
        
        switch (status) {
        case .notDetermined:
            Log.info("CLLocationManager authorization status not determined")
        case .restricted:
            Log.info("CLLocationManager authorization status restricted, can not use location services")
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
        case .denied:
            Log.info("CLLocationManager authorization status denied in user settings, can not use location services, until user enables them")
            // might consider here to ask a question to the user to enable location services again
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
        case .authorizedAlways:
            Log.info("CLLocationManager authorization status set to always authorized, we are ready to go")
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = true
            } else {
                // Fallback on earlier versions
            }
        case .authorizedWhenInUse:
            Log.info("CLLocationManager authorization status set to in use, no background updates enabled")
        
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
        }
    }
}

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
