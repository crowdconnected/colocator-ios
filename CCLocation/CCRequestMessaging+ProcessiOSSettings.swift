//
//  CCRequestMessaging+ProcessiOSSettings.swift
//  CCLocation
//
//  Created by Mobile Developer on 04/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import Foundation
import CoreLocation
import ReSwift
import CoreBluetooth

// Extension Process iOS Settings

extension CCRequestMessaging {
    
    func processIosSettings (serverMessage:Messaging_ServerMessage, store: Store<LibraryState>){
        //        DDLogVerbose("got ios settings message")
        
        if (serverMessage.hasIosSettings && !serverMessage.iosSettings.hasGeoSettings) {
            DispatchQueue.main.async {store.dispatch(DisableBackgroundGEOAction())}
            DispatchQueue.main.async {store.dispatch(DisableForegroundGEOAction())}
            DispatchQueue.main.async {store.dispatch(IsSignificationLocationChangeAction(isSignificantLocationChangeMonitoringState: false))}
            DispatchQueue.main.async {store.dispatch(DisableCurrrentGEOAction())}
        }
        
        if (serverMessage.hasIosSettings && !serverMessage.iosSettings.hasBeaconSettings) {
            DispatchQueue.main.async {store.dispatch(DisableCurrentiBeaconMonitoringAction())}
            DispatchQueue.main.async {store.dispatch(DisableForegroundiBeaconAction())}
            DispatchQueue.main.async {store.dispatch(DisableBackgroundiBeaconAction())}
            DispatchQueue.main.async {store.dispatch(DisableCurrrentiBeaconAction())}
        }
        
        if (serverMessage.hasIosSettings && !serverMessage.iosSettings.hasInertialSettings) {
            DispatchQueue.main.async {store.dispatch(DisableInertialAction())}
        }
        
        if (serverMessage.hasIosSettings && serverMessage.iosSettings.hasGeoSettings) {
            let geoSettings = serverMessage.iosSettings.geoSettings
            
            if geoSettings.hasSignificantUpates {
                
                if geoSettings.significantUpates {
                    DispatchQueue.main.async {store.dispatch(IsSignificationLocationChangeAction(isSignificantLocationChangeMonitoringState: true))}
                } else {
                    DispatchQueue.main.async {store.dispatch(IsSignificationLocationChangeAction(isSignificantLocationChangeMonitoringState: false))}
                }
            } else {
                DispatchQueue.main.async {store.dispatch(IsSignificationLocationChangeAction(isSignificantLocationChangeMonitoringState: false))}
            }
            
            if geoSettings.hasBackgroundGeo {
                configureBackgroundGEOSettings(geoSettings: geoSettings, store: store)
            } else {
                DispatchQueue.main.async {store.dispatch(DisableBackgroundGEOAction())}
            }
            
            if geoSettings.hasForegroundGeo {
                configureForegroundGEOSettings(geoSettings: geoSettings, store: store)
            } else {
                DispatchQueue.main.async {store.dispatch(DisableForegroundGEOAction())}
            }
        }
        
        if (serverMessage.hasIosSettings && serverMessage.iosSettings.hasBeaconSettings){
            
            let beaconSettings = serverMessage.iosSettings.beaconSettings
            
            if beaconSettings.hasMonitoring {
                configureMonitoringRegions(beaconSettings: beaconSettings, store: store)
            } else {
                DispatchQueue.main.async {store.dispatch(DisableCurrentiBeaconMonitoringAction())}
            }
            
            if beaconSettings.hasForegroundRanging {
                configureBeaconForegroundRangingSettings(beaconSettings: beaconSettings, store: store)
            } else {
                DispatchQueue.main.async {store.dispatch(DisableForegroundiBeaconAction())}
            }
            
            if beaconSettings.hasBackgroundRanging {
                configureBeaconBackgroundRangingSettings(beaconSettings: beaconSettings, store: store)
            } else {
                DispatchQueue.main.async {self.stateStore.dispatch(DisableBackgroundiBeaconAction())}
            }
        }
        
        if (serverMessage.hasIosSettings && serverMessage.iosSettings.hasInertialSettings) {
            
            var isInertialEnable: Bool?
            var interval: UInt32?
            
            let inertialSettings = serverMessage.iosSettings.inertialSettings
            
            if inertialSettings.hasEnabled {
                isInertialEnable = inertialSettings.enabled
            }
            
            if inertialSettings.hasInterval {
                interval = inertialSettings.interval
            }
            
            DispatchQueue.main.async {self.stateStore.dispatch(InertialStateChangedAction(isEnabled: isInertialEnable,
                                                                                          interval: interval))}
        }
    }
    
    
    public func configureBackgroundGEOSettings(geoSettings: Messaging_IosGeoSettings, store: Store<LibraryState>) {
        var activityType: CLActivityType?
        
        var maxRuntime:UInt64?
        var minOffTime:UInt64?
        
        var desiredAccuracy:Int32?
        var distanceFilter:Int32?
        var pausesUpdates:Bool?
        
        if geoSettings.backgroundGeo.hasActivityType{
            switch geoSettings.backgroundGeo.activityType {
            case Messaging_IosStandardGeoSettings.Activity.other:
                activityType = .other
            case Messaging_IosStandardGeoSettings.Activity.auto:
                activityType = .automotiveNavigation
            case Messaging_IosStandardGeoSettings.Activity.fitness:
                activityType = .fitness
            case Messaging_IosStandardGeoSettings.Activity.navigation:
                activityType = .otherNavigation
            }
        }
        
        if geoSettings.backgroundGeo.hasMaxRunTime {
            if geoSettings.backgroundGeo.maxRunTime > 0 {
                maxRuntime = geoSettings.backgroundGeo.maxRunTime
            }
        }
        
        if geoSettings.backgroundGeo.hasMinOffTime {
            if geoSettings.backgroundGeo.minOffTime > 0 {
                minOffTime = geoSettings.backgroundGeo.minOffTime
            }
        }
        
        if geoSettings.backgroundGeo.hasDistanceFilter {
            distanceFilter = geoSettings.backgroundGeo.distanceFilter
        }
        
        if geoSettings.backgroundGeo.hasDesiredAccuracy {
            desiredAccuracy = geoSettings.backgroundGeo.desiredAccuracy
        }
        
        if geoSettings.backgroundGeo.hasPausesUpdates {
            pausesUpdates = geoSettings.backgroundGeo.pausesUpdates
        }
        
        let enableBackgroundGEOAction = EnableBackgroundGEOAction(
            activityType: activityType,
            maxRuntime: maxRuntime,
            minOffTime: minOffTime,
            desiredAccuracy: desiredAccuracy,
            distanceFilter: distanceFilter,
            pausesUpdates: pausesUpdates
        )
        
        DispatchQueue.main.async {store.dispatch(enableBackgroundGEOAction)}
    }
    
    public func configureForegroundGEOSettings(geoSettings: Messaging_IosGeoSettings, store: Store<LibraryState>) {
        var activityType: CLActivityType?
        
        var maxRuntime:UInt64?
        var minOffTime:UInt64?
        
        var desiredAccuracy:Int32?
        var distanceFilter:Int32?
        var pausesUpdates:Bool?
        
        if geoSettings.foregroundGeo.hasActivityType{
            switch geoSettings.foregroundGeo.activityType {
            case Messaging_IosStandardGeoSettings.Activity.other:
                activityType = .other
            case Messaging_IosStandardGeoSettings.Activity.auto:
                activityType = .automotiveNavigation
            case Messaging_IosStandardGeoSettings.Activity.fitness:
                activityType = .fitness
            case Messaging_IosStandardGeoSettings.Activity.navigation:
                activityType = .otherNavigation
            }
        }
        
        if geoSettings.foregroundGeo.hasMaxRunTime {
            if geoSettings.foregroundGeo.maxRunTime > 0 {
                maxRuntime = geoSettings.foregroundGeo.maxRunTime
            }
        }
        
        if geoSettings.foregroundGeo.hasMinOffTime {
            if geoSettings.foregroundGeo.minOffTime > 0 {
                minOffTime = geoSettings.foregroundGeo.minOffTime
            }
        }
        
        if geoSettings.foregroundGeo.hasDistanceFilter {
            distanceFilter = geoSettings.foregroundGeo.distanceFilter
        }
        
        if geoSettings.foregroundGeo.hasDesiredAccuracy {
            desiredAccuracy = geoSettings.foregroundGeo.desiredAccuracy
        }
        
        if geoSettings.foregroundGeo.hasPausesUpdates {
            pausesUpdates = geoSettings.foregroundGeo.pausesUpdates
        }
        
        let enableForegroundGEOAction = EnableForegroundGEOAction(
            activityType: activityType,
            maxRuntime: maxRuntime,
            minOffTime: minOffTime,
            desiredAccuracy: desiredAccuracy,
            distanceFilter: distanceFilter,
            pausesUpdates: pausesUpdates
        )
        
        DispatchQueue.main.async {store.dispatch(enableForegroundGEOAction)}
    }
    
    public func configureMonitoringRegions(beaconSettings: Messaging_IosBeaconSettings, store: Store<LibraryState>) {
        let monitoringSettings = beaconSettings.monitoring
        
        var monitoringRegions: [CLBeaconRegion] = []
        
        for region in monitoringSettings.regions {
            if region.hasUuid {
                if region.hasMajor {
                    if region.hasMinor{
                        if let uuid = UUID(uuidString: region.uuid) {
                            monitoringRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), minor: CLBeaconMinorValue(region.minor), identifier: "CC \(region.uuid):\(region.major):\(region.minor)"))
                        }
                    } else {
                        if let uuid = UUID(uuidString: region.uuid) {
                            monitoringRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), identifier: "CC \(region.uuid):\(region.major)"))
                        }
                    }
                }
                else {
                    if let uuid = UUID(uuidString: region.uuid) {
                        monitoringRegions.append(CLBeaconRegion(proximityUUID: uuid, identifier: "CC \(region.uuid)"))
                    }
                }
            }
        }
        
        DispatchQueue.main.async {store.dispatch(EnableCurrentiBeaconMonitoringAction(monitoringRegions: monitoringRegions.sorted(by: {$0.identifier < $1.identifier})))}
    }
    
    public func configureBeaconForegroundRangingSettings(beaconSettings: Messaging_IosBeaconSettings, store: Store<LibraryState>) {
        let foregroundRanging = beaconSettings.foregroundRanging
        
        var excludeRegions: [CLBeaconRegion] = []
        var rangingRegions: [CLBeaconRegion] = []
        
        var maxRuntime:UInt64?
        var minOffTime:UInt64?
        var filterWindowSize:UInt64?
        var maxObservations:UInt32?
        
        var eddystoneScan:Bool?
        
        for region in foregroundRanging.regions {
            if region.hasUuid {
                if region.hasMajor {
                    if region.hasMinor{
                        if let uuid = UUID(uuidString: region.uuid) {
                            rangingRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), minor: CLBeaconMinorValue(region.minor), identifier: "CC \(region.uuid):\(region.major):\(region.minor)"))
                        }
                    } else {
                        if let uuid = UUID(uuidString: region.uuid) {
                            rangingRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), identifier: "CC \(region.uuid):\(region.major)"))
                        }
                    }
                }
                else {
                    if let uuid = UUID(uuidString: region.uuid) {
                        rangingRegions.append(CLBeaconRegion(proximityUUID: uuid, identifier: "CC \(region.uuid)"))
                    }
                }
            }
        }
        
        
        for region in foregroundRanging.filter.excludeRegions {
            if region.hasUuid {
                if region.hasMajor {
                    if region.hasMinor{
                        if let uuid = UUID(uuidString: region.uuid) {
                            excludeRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), minor: CLBeaconMinorValue(region.minor), identifier: "CC \(region.uuid):\(region.major):\(region.minor)"))
                        }
                    } else {
                        if let uuid = UUID(uuidString: region.uuid) {
                            excludeRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), identifier: "CC \(region.uuid):\(region.major)"))
                        }
                    }
                }
                else {
                    if let uuid = UUID(uuidString: region.uuid) {
                        excludeRegions.append(CLBeaconRegion(proximityUUID: uuid, identifier: "CC \(region.uuid)"))
                    }
                }
            }
        }
        
        if foregroundRanging.hasMaxRunTime {
            if foregroundRanging.maxRunTime > 0 {
                maxRuntime = foregroundRanging.maxRunTime
            }
        }
        
        if foregroundRanging.hasMinOffTime {
            if foregroundRanging.minOffTime > 0 {
                minOffTime = foregroundRanging.minOffTime
            }
        }
        
        if foregroundRanging.hasFilter {
            let filter = foregroundRanging.filter
            
            if filter.hasWindowSize {
                if filter.windowSize > 0 {
                    filterWindowSize = filter.windowSize
                }
            }
            
            if filter.hasMaxObservations {
                if filter.maxObservations > 0 {
                    maxObservations = filter.maxObservations
                }
            }
        }
        
        if foregroundRanging.hasEddystoneScan {
            eddystoneScan = foregroundRanging.eddystoneScan
        }
        
        let isIBeaconRangingEnabled = rangingRegions.count > 0 ? true : false
        
        DispatchQueue.main.async {store.dispatch(EnableForegroundBeaconAction(maxRuntime: maxRuntime,
                                                                              minOffTime: minOffTime,
                                                                              regions: rangingRegions.sorted(by: {$0.identifier < $1.identifier}),
                                                                              filterWindowSize: filterWindowSize,
                                                                              filterMaxObservations: maxObservations,
                                                                              filterExcludeRegions: excludeRegions.sorted(by: {$0.identifier < $1.identifier}),
                                                                              isEddystoneScanEnabled: eddystoneScan,
                                                                              isIBeaconRangingEnabled: isIBeaconRangingEnabled))}
    }
    
    public func configureBeaconBackgroundRangingSettings(beaconSettings: Messaging_IosBeaconSettings, store: Store<LibraryState>) {
        let backgroundRanging = beaconSettings.backgroundRanging
        
        var excludeRegions: [CLBeaconRegion] = []
        var rangingRegions: [CLBeaconRegion] = []
        
        var maxRuntime:UInt64?
        var minOffTime:UInt64?
        var filterWindowSize:UInt64?
        var maxObservations:UInt32?
        
        var eddystoneScan: Bool?
        
        for region in backgroundRanging.regions {
            if region.hasUuid {
                if region.hasMajor {
                    if region.hasMinor{
                        if let uuid = UUID(uuidString: region.uuid) {
                            rangingRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), minor: CLBeaconMinorValue(region.minor), identifier: "CC \(region.uuid):\(region.major):\(region.minor)"))
                        }
                    } else {
                        if let uuid = UUID(uuidString: region.uuid) {
                            rangingRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), identifier: "CC \(region.uuid):\(region.major)"))
                        }
                    }
                }
                else {
                    if let uuid = UUID(uuidString: region.uuid) {
                        rangingRegions.append(CLBeaconRegion(proximityUUID: uuid, identifier: "CC \(region.uuid)"))
                    }
                }
            }
        }
        
        for region in backgroundRanging.filter.excludeRegions {
            if region.hasUuid {
                if region.hasMajor {
                    if region.hasMinor{
                        if let uuid = UUID(uuidString: region.uuid) {
                            excludeRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), minor: CLBeaconMinorValue(region.minor), identifier: "CC \(region.uuid):\(region.major):\(region.minor)"))
                        }
                    } else {
                        if let uuid = UUID(uuidString: region.uuid) {
                            excludeRegions.append(CLBeaconRegion(proximityUUID: uuid , major: CLBeaconMajorValue(region.major), identifier: "CC \(region.uuid):\(region.major)"))
                        }
                    }
                }
                else {
                    if let uuid = UUID(uuidString: region.uuid) {
                        excludeRegions.append(CLBeaconRegion(proximityUUID: uuid, identifier: "CC \(region.uuid)"))
                    }
                }
            }
        }
        
        
        if backgroundRanging.hasMaxRunTime {
            if backgroundRanging.maxRunTime > 0 {
                maxRuntime = backgroundRanging.maxRunTime
            }
        }
        
        if backgroundRanging.hasMinOffTime {
            if backgroundRanging.minOffTime > 0 {
                minOffTime = backgroundRanging.minOffTime
            }
        }
        
        if backgroundRanging.hasFilter {
            let filter = backgroundRanging.filter
            
            if filter.hasWindowSize {
                if filter.windowSize > 0 {
                    filterWindowSize = filter.windowSize
                }
            }
            
            if filter.hasMaxObservations {
                if filter.maxObservations > 0 {
                    maxObservations = filter.maxObservations
                }
                
            }
        }
        
        if backgroundRanging.hasEddystoneScan {
            eddystoneScan = backgroundRanging.eddystoneScan
        }
        
        let isIBeaconRangingEnabled = rangingRegions.count > 0 ? true : false
        
        DispatchQueue.main.async {self.stateStore.dispatch(EnableBackgroundiBeaconAction(maxRuntime: maxRuntime,
                                                                                         minOffTime: minOffTime,
                                                                                         regions: rangingRegions.sorted(by: {$0.identifier < $1.identifier}),
                                                                                         filterWindowSize: filterWindowSize,
                                                                                         filterMaxObservations: maxObservations,
                                                                                         filterExcludeRegions: excludeRegions.sorted(by: {$0.identifier < $1.identifier}),
                                                                                         eddystoneScanEnabled: eddystoneScan,
                                                                                         isIBeaconRangingEnabled: isIBeaconRangingEnabled))}
    }
}
