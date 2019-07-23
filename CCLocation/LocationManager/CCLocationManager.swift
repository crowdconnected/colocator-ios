//
//  CCLocationManager.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 23/07/2017.
//  Copyright © 2017 Crowd Connected. All rights reserved.
//

import Foundation
import CoreLocation
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
    internal var eddystoneBeaconScanner: BeaconScanner? = nil
    
    internal var currentGEOState: CurrentGEOState!
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
    
    public weak var delegate:CCLocationManagerDelegate?
    
    weak var stateStore: Store<LibraryState>!
    
    public init(stateStore: Store<LibraryState>) {
        super.init()
        
        UserDefaults.standard.set(true, forKey: "CollectLocationDataKEY")
        
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

        UserDefaults.standard.set(false, forKey: "CollectLocationDataKEY")
        
        locationManager.stopUpdatingLocation()
        stopReceivingSignificantLocationChanges()
        stopRangingiBeacons(forCurrentSettings: false)
        stopMonitoringForBeaconRegions()
        locationManager.delegate = nil
        centralManager?.delegate = nil
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
}

// MARK:- Responding to Location Events
extension CCLocationManager {
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        Log.debug("Received \(locations.count) locations")
        
        for location in locations {
            Log.debug("Geolocation information: \(location.description)")
            
            //            if #available(iOS 10.0, *) {
            //                let content = UNMutableNotificationContent()
            //                content.title = "GEO location event"
            //                content.body = "\(location.description)"
            //                content.sound = .default()
            //
            //                let request = UNNotificationRequest(identifier: "GEOLocation", content: content, trigger: nil)
            //                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
            //
            //            }
            
            delegate?.receivedGEOLocation(location: location)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        switch (error) {
        case CLError.headingFailure:
            Log.error(String(format:"locationManager didFailWithError kCLErrorHeadingFailure occured with description: %@", error.localizedDescription))
            break
            
        // as per Apple documentation, locationUnknown error occures when the location service is unable to retrieve a location right away, but keeps trying, simply to ignore and wait for new event
        case CLError.locationUnknown:
            Log.error(String(format:"locationManager didFailWithError kCLErrorLocationUnknown occured with description: %@", error.localizedDescription))
            break
            
        // as per Apple documentation, denied error occures when the user denies location services, if that happens we should stop location services
        case CLError.denied:
            Log.error(String(format:"locationManager didFailWithError kCLErrorDenied occured with description: %@", error.localizedDescription))
            
            // According to API reference on denied error occures, when users stops location services, so we should stop them as well here
            
            // TODO: wrap into stop function to stop everything
            //            self.locationManager.stopUpdatingLocation()
            //            self.locationManager.stopMonitoringSignificantLocationChanges()
            break
            
        default:
            Log.error(String(format:"locationManager didFailWithError Unknown location error occured with description: %@", error.localizedDescription));
            break
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        Log.error("Did finish deferred updates with error \(error?.localizedDescription ?? "nil"))")
    }
}

// MARK: - Responding to Eddystone Beacon Discovery Events
extension CCLocationManager: BeaconScannerDelegate {
    func didFindBeacon(beaconScanner: BeaconScanner, beaconInfo: EddystoneBeaconInfo) {
        
        Log.verbose("FIND: \(beaconInfo.description)")
        
        if (beaconInfo.beaconID.beaconType == BeaconID.BeaconType.EddystoneEID){
            
            var isFilterAvailable = false
            checkIfWindowSizeAndMaxObservationsAreAvailable(&isFilterAvailable)
            
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
            checkIfWindowSizeAndMaxObservationsAreAvailable(&isFilterAvailable)
            
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
        //
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
            Log.debug("Did start monitoring for region: \(beaconRegion.identifier) uuid: \(beaconRegion.proximityUUID) major: \(String(describing: beaconRegion.major)) minor: \(String(describing: beaconRegion.minor))")

            Log.verbose("------- a list of monitored regions -------")
            for monitoredRegion in locationManager.monitoredRegions {
                Log.verbose("\(monitoredRegion)")
            }
            Log.verbose("------- list end -------")
        }
    }
}

// MARK: - Responding to Ranging Events
extension CCLocationManager {
    
    fileprivate func checkIfWindowSizeAndMaxObservationsAreAvailable(_ isFilterAvailable: inout Bool) {
        
        if let windowSize = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterWindowSize {
            if let maxObservations = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterMaxObservations {
                if windowSize > 0 && maxObservations > 0 {
                    isFilterAvailable = true
                }
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
        
        if (beacons.count > 0){
            for beacon in beacons {
                
                Log.verbose("Ranged beacon with UUID: \(beacon.proximityUUID.uuidString), MAJOR: \(beacon.major), MINOR: \(beacon.minor), RSSI: \(beacon.rssi)")
                
                //                if #available(iOS 10.0, *) {
                //                    let content = UNMutableNotificationContent()
                //                    content.title = "iBeacon ranged"
                //                    content.body = "UUID: \(beacon.proximityUUID.uuidString), MAJ: \(beacon.major), MIN: \(beacon.minor), RSSI: \(beacon.rssi)"
                //                    content.sound = .default()
                //
                //                    let request = UNNotificationRequest(identifier: "GEOLocation", content: content, trigger: nil)
                //                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                //                }
                
                // mainly excluding RSSI's that are zero, which happens some time
                if beacon.rssi < 0 {
                    
                    var isFilterAvailable: Bool = false
                    checkIfWindowSizeAndMaxObservationsAreAvailable(&isFilterAvailable)
                    
                    // check if exclude regions
                    if let excludeRegions = stateStore.state.locationSettingsState.currentLocationState?.currentBeaconState?.filterExcludeRegions{
                        let results = Array(excludeRegions.filter { region in
                            return checkRegionBelonging(region, beacon: beacon)
                        })
                        
                        if results.count > 0 {
                            Log.debug("Beacon is in exclude regions")
                        } else {
                            Log.debug("Beacon is input to reporting")
                            
                            if isFilterAvailable {
                                insert(beacon: beacon)
                            } else {
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
                        }
                    } else {
                        if isFilterAvailable {
                            insert(beacon: beacon)
                        } else {
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
        
        Log.debug("Changed authorization status")
        
        DispatchQueue.main.async {self.stateStore.dispatch(LocationAuthStatusChangedAction(locationAuthStatus: status))}
        DispatchQueue.main.async {self.stateStore.dispatch(IsLocationServicesEnabledAction(isLocationServicesEnabled: CLLocationManager.locationServicesEnabled()))}
        
        switch (status) {
        case .notDetermined:
            Log.info("CLLocationManager authorization status not determined")
            
            break
            
        case .restricted:
             Log.info("CLLocationManager authorization status restricted, can not use location services")
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
            
            break
            
        case .denied:
            Log.info("CLLocationManager authorization status denied in user settings, can not use location services, until user enables them")
            // might consider here to ask a question to the user to enable location services again
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
            
            break
            
        case .authorizedAlways:
            Log.info("CLLocationManager authorization status set to always authorized, we are ready to go")
            
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = true
            } else {
                // Fallback on earlier versions
            }
            
            break
            
        case .authorizedWhenInUse:
            Log.info("CLLocationManager authorization status set to in use, no background updates enabled")
        
            if #available(iOS 9.0, *) {
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                // Fallback on earlier versions
            }
            
            break
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
