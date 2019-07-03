//
//  CCRequestMessaging.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 16/10/2016.
//  Copyright © 2016 Crowd Connected. All rights reserved.
//

import Foundation
import CoreLocation
import ReSwift
import CoreBluetooth // only needed for state reporting - CBCentralManagerState enum
//import os.log

class CCRequestMessaging: NSObject {
    
    weak var timeBetweenSendsTimer: Timer?
    
    enum MessageType {
        case queueable
        case discardable
    }
    
    weak var ccSocket: CCSocket?
    weak var stateStore: Store<LibraryState>!
    weak var timeHandling: TimeHandling!
    
    var currentRadioSilenceTimerState: TimerState?
    var currentWebSocketState: WebSocketState?
    var currentLibraryTimerState: LibraryTimeState?
    var currentCapabilityState: CapabilityState?
    
    var workItems: [DispatchWorkItem] = []
    
    internal var messagesDB: SQLiteDatabase!
    internal let messagesDBName = "observations.db"
    
    init(ccSocket: CCSocket, stateStore: Store<LibraryState>) {
        super.init()
        
        self.ccSocket = ccSocket
        self.stateStore = stateStore
        
        timeHandling = TimeHandling.shared
        timeHandling.delegate = self
        
        stateStore.subscribe(self)
        {
            $0.select {
                state in state.ccRequestMessagingState
            }
        }
        
        if (stateStore.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime == nil){
            timeHandling.fetchTrueTime()
        }
        
        openMessagesDatabase()
        createCCMesageTable()
        
        setupApplicationNotifications()
        setupBatteryStateAndLevelNotifcations()
        
        //initial dispatch of battery state
        batteryStateDidChange(notification: Notification(name: UIDevice.batteryStateDidChangeNotification))
    }
    
    // MARK: - PROCESS RECEIVED COLOCATOR SERVER MESSAGES FUNCTIONS
    public func processServerMessage(data:Data) throws {
        let serverMessage = try Messaging_ServerMessage.init(serializedData: data)
        
        Log.debug("Received a server message: ")
        Log.debug("\(serverMessage)")
        
        processGlobalSettings(serverMessage: serverMessage, store: stateStore)
        processIosSettings(serverMessage: serverMessage, store: stateStore)
        
        //        processBTSettings(serverMessage: serverMessage)
        //        processSystemBeacons(serverMessage: serverMessage)
        //        [self processTextMessageWrapper:serverMessage];
    }
    
    func processGlobalSettings(serverMessage:Messaging_ServerMessage, store: Store<LibraryState>) {
        
        if (serverMessage.hasGlobalSettings) {
            //            DDLogVerbose("got global settings message")
            
            let globalSettings = serverMessage.globalSettings
            
            if globalSettings.hasRadioSilence {
                
                // if radio silence is 0 treat it the same way as if the timer doesn't exist
                if globalSettings.radioSilence != 0 {
                    DispatchQueue.main.async {
                        store.dispatch(TimeBetweenSendsTimerReceivedAction(timeInMilliseconds: globalSettings.radioSilence))
                    }
                } else {
                    DispatchQueue.main.async {
                        store.dispatch(TimeBetweenSendsTimerReceivedAction(timeInMilliseconds: nil))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    store.dispatch(TimeBetweenSendsTimerReceivedAction(timeInMilliseconds: nil))
                }
            }
            
            if globalSettings.hasID {
                let uuid = NSUUID(uuidBytes: ([UInt8](globalSettings.id)))
                ccSocket?.setDeviceId(deviceId: uuid.uuidString)
            }
        }
    }
    
    //- (void) processTextMessageWrapper:(Messaging::ServerMessage*) serverMessage {
    //    if (serverMessage->has_message()){
    //        CCFastLog(@"got a notification message wrapper");
    //
    //
    //        NSString* wrapperId = [NSString stringWithCString:serverMessage->message().id().c_str() encoding:[NSString defaultCStringEncoding]];
    //
    //        NSMutableDictionary* messagesWrapper = [NSMutableDictionary dictionaryWithDictionary:@{@"wrapperId": wrapperId}];
    //        NSMutableArray* messages = [[NSMutableArray alloc] init];
    //
    //        NSDate *currentTime = [NSDate date];
    //        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    //        [dateFormatter setDateFormat:@"HH:mm"];
    //        NSString *currentTimeString = [dateFormatter stringFromDate: currentTime];
    //
    //        for(int i = 0; i < serverMessage->message().messages_size(); i++){
    //            [messages addObject: @{@"title": [NSString stringWithCString:serverMessage->message().messages(i).title().c_str() encoding:[NSString defaultCStringEncoding]],
    //                                   @"language": [NSString stringWithCString:serverMessage->message().messages(i).language().c_str() encoding:[NSString defaultCStringEncoding]],
    //                                   @"text": [NSString stringWithCString:serverMessage->message().messages(i).text().c_str() encoding:[NSString defaultCStringEncoding]],
    //                                   @"description": [NSString stringWithCString:serverMessage->message().messages(i).description().c_str() encoding:[NSString defaultCStringEncoding]],
    //                                   @"time": currentTimeString}];
    //
    //
    //        }
    //
    //        [messagesWrapper setObject:messages forKey:@"messages"];
    //
    //        [self sendAcknowledgement:wrapperId];
    //
    //        [self.delegate receivedTextMessage:messagesWrapper];
    //    }
    //}
    
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
            } else {
                DispatchQueue.main.async {store.dispatch(DisableBackgroundGEOAction())}
            }
            
            if geoSettings.hasForegroundGeo {
                
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
            } else {
                DispatchQueue.main.async {store.dispatch(DisableForegroundGEOAction())}
            }
        }
        
        if (serverMessage.hasIosSettings && serverMessage.iosSettings.hasBeaconSettings){
            
            let beaconSettings = serverMessage.iosSettings.beaconSettings
            
            if beaconSettings.hasMonitoring {
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
            } else {
                DispatchQueue.main.async {store.dispatch(DisableCurrentiBeaconMonitoringAction())}
            }
            
            if beaconSettings.hasForegroundRanging {
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
            } else {
                DispatchQueue.main.async {store.dispatch(DisableForegroundiBeaconAction())}
            }
            
            if beaconSettings.hasBackgroundRanging {
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
    
    //    func processSystemBeacons(serverMessage:Messaging_ServerMessage) {
    //
    //        if (serverMessage.beacon.count > 0) {
    //            DDLogDebug("Got an iBeacon message")
    //
    //            var beaconUUIDs: [String] = []
    //
    //            for beacon in serverMessage.beacon {
    //                beaconUUIDs.append(beacon.identifier)
    //            }
    //
    //            ccRequest.setiBeaconProximityUUIDsSwiftBridge(beaconUUIDs)
    //        }
    //    }
    
    //    func processBTSettings(serverMessage:Messaging_ServerMessage) {
    //
    //        if (serverMessage.btSettings.count > 0) {
    //            DDLogDebug("got BT settings")
    //
    //            for btSetting in serverMessage.btSettings {
    //                let btleAltBeaconScanTime = Double(btSetting.btleAltBeaconScanTime) / 1000.0
    //                let btleBeaconScanTime = Double(btSetting.btleBeaconScanTime) / 1000.0
    //                let btleAdvertiseTime = Double(btSetting.btleAdvertiseTime) / 1000.0
    //                let idleTime = Double(btSetting.idleTime) / 1000.0
    //                let offTime = Double(btSetting.offTime) / 1000.0
    //                let altBeaconScan = btSetting.altBeaconScan
    //                let batchWindow = Double(btSetting.batchWindow) / 1000.0
    //
    //                var state:String?
    //
    //                if (btSetting.hasState){
    //                    state = "OFFLINE"
    //                } else {
    //                    state = nil
    //                }
    //
    //                ccRequest.updateBTSettingsSwiftBridge(NSNumber(value: btleAltBeaconScanTime), btleBeaconScanTime:NSNumber(value:btleBeaconScanTime), btleAdvertiseTime: NSNumber(value:btleAdvertiseTime), idleTime: NSNumber(value:idleTime), offTime: NSNumber(value:offTime), altBeaconScan: altBeaconScan, batchWindow: NSNumber(value:batchWindow), state: state)
    //            }
    //        }
    //    }
    
    // MARK: - EVENT PROCESSING FUNCTIONS
    
    public func processIBeaconEvent(uuid:UUID, major:Int, minor:Int, rssi:Int, accuracy:Double, proximity:Int, timestamp:TimeInterval){
        
        let uuidData = uuid.uuidString.data(using: .utf8)
        
        var clientMessage = Messaging_ClientMessage()
        var iBeaconMessage = Messaging_IBeacon()
        
        iBeaconMessage.uuid = uuidData!
        iBeaconMessage.major = UInt32(major)
        iBeaconMessage.minor = UInt32(minor)
        iBeaconMessage.rssi = Int32(rssi)
        iBeaconMessage.accuracy = accuracy
        
        iBeaconMessage.timestamp = UInt64(timestamp * 1000)
        
        iBeaconMessage.proximity = UInt32(proximity)
        
        clientMessage.ibeaconMessage.append(iBeaconMessage)
        
        //        Log.debug("iBeacon message built: \(clientMessage)")
        
        if let data = try? clientMessage.serializedData(){
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
    public func processEddystoneEvent(eid:Data, tx:Int, rssi:Int, timestamp:TimeInterval){
        
        var clientMessage = Messaging_ClientMessage()
        var eddyStoneMessage = Messaging_EddystoneBeacon()
        
        eddyStoneMessage.eid = eid
        eddyStoneMessage.rssi = Int32(rssi)
        eddyStoneMessage.timestamp = UInt64(timestamp * 1000)
        eddyStoneMessage.tx = Int32(tx)
        
        clientMessage.eddystonemessage.append(eddyStoneMessage)
        
        Log.verbose("Eddystone beacon message build: \(clientMessage)")
        
        if let data = try? clientMessage.serializedData(){
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
    public func processBluetoothEvent(uuid:UUID, rssi:Int, timeInterval:TimeInterval) {
        
        let uuidData = uuid.uuidString.data(using: .utf8)
        
        var clientMessage = Messaging_ClientMessage()
        var bluetoothMessage = Messaging_Bluetooth()
        
        //        var uuidBytes: [UInt8] = [UInt8](repeating: 0, count: 16)
        //        uuid.getBytes(&uuidBytes)
        //        let uuidData = NSData(bytes: &uuidBytes, length: 16)
        
        bluetoothMessage.identifier = uuidData!
        bluetoothMessage.rssi = Int32(rssi)
        bluetoothMessage.tx = 0
        bluetoothMessage.timestamp = UInt64(fabs(timeInterval * Double(1000.0)))
        
        clientMessage.bluetoothMessage.append(bluetoothMessage)
        
        //DDLogVerbose ("Bluetooth message build: \(clientMessage)")
        
        if let data = try? clientMessage.serializedData() {
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
    
    
    //    func sendCollatedBluetoothMessage(devices:Dictionary<String, Dictionary<String, Int>>, timeInterval:TimeInterval) {
    //
    //        var clientMessage = Messaging_ClientMessage()
    //
    //        for key in devices.keys {
    //
    //            var bluetoothMessage = Messaging_Bluetooth()
    //
    //            let peripheralUUID = NSUUID.init(uuidString: key)
    //
    //            var uuidBytes: [UInt8] = [UInt8](repeating: 0, count: 16)
    //            peripheralUUID?.getBytes(&uuidBytes)
    //            let uuidData = NSData(bytes: &uuidBytes, length: 16)
    //
    //            bluetoothMessage.identifier = uuidData as Data
    //            bluetoothMessage.rssi = Int32(devices[key]!["proximity"]!)
    //            bluetoothMessage.tx = 0
    //            bluetoothMessage.amountAveraged = UInt32(devices[key]!["amountAveraged"]!)
    //            bluetoothMessage.timestamp = UInt64(fabs(timeInterval * Double(1000.0)))
    //
    //            clientMessage.bluetoothMessage.append(bluetoothMessage)
    //        }
    //
    //        DDLogVerbose ("Collated Bluetooth message build: \(clientMessage)")
    //
    //        if let data = try? clientMessage.serializedData(){
    //            sendClientMessage(data: data, messageType: .queueable)
    //        }
    //    }
    
    public func processLocationEvent(location:CLLocation) {
        
        let userDefaults = UserDefaults.standard
        
        var clientMessage = Messaging_ClientMessage()
        var locationMessage = Messaging_LocationMessage()
        
        var counter = userDefaults.integer(forKey: CCRequestMessagingConstants.messageCounter)
        
        if counter < Int.max {
            counter = counter + 1
        } else {
            counter = 0
        }
        
        locationMessage.longitude = location.coordinate.longitude
        locationMessage.latitude = location.coordinate.latitude
        locationMessage.horizontalAccuracy = location.horizontalAccuracy
        locationMessage.verticalAccuracy = location.verticalAccuracy
        locationMessage.course = Double(counter)
        locationMessage.speed = 1
        
        // a negative value for vertical accuracy indicates that the altitude value is invalid
        if (location.verticalAccuracy >= 0){
            locationMessage.altitude = location.altitude
        }
        
        let trueTimeSame = timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket)
        
        if ((stateStore.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime) != nil || trueTimeSame) {
            
            let lastSystemTime = stateStore.state.ccRequestMessagingState.libraryTimeState?.systemTimeAtLastTrueTime
            
            let currentTime = Date()
            
            let beetweenSystemsTimeInterval = currentTime.timeIntervalSince(lastSystemTime!)
            
            let sendTimeInterval = stateStore.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime?.addingTimeInterval(beetweenSystemsTimeInterval).timeIntervalSince1970
            
            locationMessage.timestamp = UInt64(sendTimeInterval! * 1000)
            
            if !trueTimeSame {
                locationMessage.speed = -1
            }
        } else {
            locationMessage.timestamp = UInt64(0)
        }
        
        clientMessage.locationMessage.append(locationMessage)
        
        if let data = try? clientMessage.serializedData(){
            //            NSLog("Location message build: \(clientMessage) with size: \(String(describing: data.count))")
            userDefaults.set(counter, forKey: CCRequestMessagingConstants.messageCounter)
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
    public func processStep(date: Date, angle: Double) {
        
        var clientMessage = Messaging_ClientMessage()
        var stepMessage = Messaging_Step()
        
        stepMessage.angle = angle
        
        let trueTimeSame = timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket)
        
        if ((stateStore.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime) != nil || trueTimeSame) {
            
            let lastSystemTime = stateStore.state.ccRequestMessagingState.libraryTimeState?.systemTimeAtLastTrueTime
            
            let beetweenSystemsTimeInterval = date.timeIntervalSince(lastSystemTime!)
            
            let sendTimeInterval = stateStore.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime?.addingTimeInterval(beetweenSystemsTimeInterval).timeIntervalSince1970
            
            stepMessage.timestamp = UInt64(sendTimeInterval! * 1000)
        }
        
        clientMessage.step.append(stepMessage)
        
        if let data = try? clientMessage.serializedData(){
//            NSLog("Step message build: \(clientMessage) with size: \(String(describing: data.count))")
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
    
    public func processIOSCapability(locationAuthStatus: CLAuthorizationStatus?,
                                     bluetoothHardware: CBCentralManagerState?,
                                     batteryState: UIDevice.BatteryState?,
                                     isLowPowerModeEnabled: Bool?,
                                     isLocationServicesEnabled: Bool?){
        
        var clientMessage = Messaging_ClientMessage()
        
        var capabilityMessage = Messaging_IosCapability()
        
        if let locationServices = isLocationServicesEnabled {
            capabilityMessage.locationServices = locationServices
        }
        
        if let lowPowerMode = isLowPowerModeEnabled {
            capabilityMessage.lowPowerMode = lowPowerMode
        }
        
        if let locationAuthStatus = locationAuthStatus {
            switch locationAuthStatus {
            case .authorizedAlways:
                capabilityMessage.locationAuthStatus = Messaging_IosCapability.LocationAuthStatus.always
            case .authorizedWhenInUse:
                capabilityMessage.locationAuthStatus = Messaging_IosCapability.LocationAuthStatus.inUse
            case .denied:
                capabilityMessage.locationAuthStatus = Messaging_IosCapability.LocationAuthStatus.denied
            case .notDetermined:
                capabilityMessage.locationAuthStatus = Messaging_IosCapability.LocationAuthStatus.notDetermined
            case .restricted:
                capabilityMessage.locationAuthStatus = Messaging_IosCapability.LocationAuthStatus.restricted
            }
        }
        
        if let bluetoothHardware = bluetoothHardware {
            switch bluetoothHardware {
            case .poweredOff:
                capabilityMessage.bluetoothHardware = Messaging_IosCapability.BluetoothHardware.off
            case .poweredOn:
                capabilityMessage.bluetoothHardware = Messaging_IosCapability.BluetoothHardware.on
            case .resetting:
                capabilityMessage.bluetoothHardware = Messaging_IosCapability.BluetoothHardware.resetting
            case .unauthorized:
                capabilityMessage.bluetoothHardware = Messaging_IosCapability.BluetoothHardware.unauthorized
            case .unknown:
                capabilityMessage.bluetoothHardware = Messaging_IosCapability.BluetoothHardware.unknown
            case .unsupported:
                capabilityMessage.bluetoothHardware = Messaging_IosCapability.BluetoothHardware.unsupported
            }
        }
        
        if let batteryState = batteryState {
            switch batteryState{
            case .charging:
                capabilityMessage.batteryState = Messaging_IosCapability.BatteryState.charging
            case .full:
                capabilityMessage.batteryState = Messaging_IosCapability.BatteryState.full
            case .unknown:
                capabilityMessage.batteryState = Messaging_IosCapability.BatteryState.notDefined
            case .unplugged:
                capabilityMessage.batteryState = Messaging_IosCapability.BatteryState.unplugged
            }
        }
        
        clientMessage.iosCapability = capabilityMessage
        
        if let data = try? clientMessage.serializedData(){
            //            Log.debug("Capability message build: \(clientMessage) with size: \(String(describing: data.count))")
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
    public func processAliases(aliases:Dictionary<String,String>) {
        
        var clientMessage = Messaging_ClientMessage()
        
        for key in aliases.keys{
            
            var aliasMessage = Messaging_AliasMessage()
            
            aliasMessage.key = key
            aliasMessage.value = aliases[key]!
            
            clientMessage.alias.append(aliasMessage)
        }
        
        //DDLogVerbose ("alias message build: \(clientMessage)")
        
        if let data = try? clientMessage.serializedData() {
            sendOrQueueClientMessage(data: data, messageType: .discardable)
        }
    }
    
    public func processMarker(data:String) {
        
        if let timeInterval = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
            
            var clientMessage = Messaging_ClientMessage()
            var markerMessage = Messaging_MarkerMessage()
            
            markerMessage.data = data
            markerMessage.time = UInt64(fabs(timeInterval * Double(1000.0)))
            
            clientMessage.marker = markerMessage
            
            //DDLogVerbose ("marker message build: \(clientMessage)")
            
            if let data = try? clientMessage.serializedData() {
                sendOrQueueClientMessage(data: data, messageType: .queueable)
            }
        }
    }
    
    //- (void) sendAcknowledgement:(NSString*)messageId {
    //
    //
    //    std::string ackString ([(NSString*)messageId UTF8String]);
    //
    //    Messaging::ClientMessage *clientMessage = new Messaging::ClientMessage();
    //
    //    Messaging::Acknowledgement *ackMessage = new Messaging::Acknowledgement();
    //
    //    ackMessage->set_id(ackString);
    //
    //    clientMessage->set_allocated_ack(ackMessage);
    //
    //    // Some small tomfoolery required to go from C++ std::string to NSString.
    //    std::string x = clientMessage->DebugString();
    //    NSString *output = [NSString stringWithCString:x.c_str() encoding:[NSString defaultCStringEncoding]];
    //    CCFastLog(@"Acknowledgement message: %@", output);
    //
    //    [self sendClientMessage:[self getDataForClientMessage:clientMessage] queuable:TRUE];
    //}
    
    
    // MARK: - STATE HANDLING FUNCTIONS
    
    public func webSocketDidOpen() {
        if stateStore != nil {
            DispatchQueue.main.async {self.stateStore.dispatch(WebSocketAction(connectionState: ConnectionState.online))}
        }
    }
    
    public func webSocketDidClose() {
        if stateStore != nil {
            DispatchQueue.main.async {self.stateStore.dispatch(WebSocketAction(connectionState: ConnectionState.offline))}
        }
    }
    
    // MARK: - HIGH LEVEL SEND CLIENT MESSAGE DATA
    
    func sendOrQueueClientMessage(data: Data, messageType:MessageType) {
        
        let connectionState = stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
        let timeBetweenSends = stateStore.state.ccRequestMessagingState.radiosilenceTimerState?.timeInterval
        
        sendOrQueueClientMessage(data: data, messageType: messageType, connectionState: connectionState, timeBetweenSends: timeBetweenSends)
    }
    
    func sendOrQueueClientMessage(data: Data, messageType:MessageType, connectionState: ConnectionState?, timeBetweenSends: UInt64?) {
        
        var isConnectionAvailable: Bool = false
        
        if let connectionStateUnwrapped = connectionState {
            
            if (connectionStateUnwrapped == .online) {
                
                isConnectionAvailable = true
                // case for iBeacon + GEO + Marker + Alias + Bluetooth + Latency messages and buffer timer not set
                if (timeBetweenSends == nil || timeBetweenSends == 0){
                    Log.verbose("Websocket is open, buffer timer is not available, sending new and queued messages")
                    self.sendQueuedClientMessages(firstMessage: data)
                } else {
                    // case for iBeacon + GEO + Marker + Alias + Bluetooth messages, when buffer timer is set
                    if (messageType == .queueable){
                        //                        Log.verbose("Message is queuable, buffer timer active, going to queue message")
                        
                        insertMessageInLocalDatabase(message: data)
                    }
                    
                    // case for Latency Message, when buffer timer is set
                    if (messageType == .discardable){
                        //DDLogVerbose("Message is discardable (most likely latency message), buffer timer active, Websocket is online, sending new and queued messages")
                        sendQueuedClientMessages(firstMessage: data)
                    }
                }
            }
        }
        
        // we want to guard the execution of the next statements for the case ConnectionState.offline and if there was no connectionState available in the first place
        guard isConnectionAvailable == false else {
            return
        }
        
        // case for iBeacon + GEO + Marker + Alias messages, when offline
        if (messageType == .queueable){
            //            Log.verbose("Websocket is offline, message is queuable, going to queue message")
            insertMessageInLocalDatabase(message: data)
        }
        
        // case for Latency message, when offline
        if (messageType == .discardable){
            Log.verbose("Websocket offline, message discardable, going to discard message")
        }
    }
    
    // sendQueuedClientMessage for timeBetweenSendsTimer firing
    @objc internal func sendQueuedClientMessagesTimerFired(){
        Log.verbose("flushing queued messages")
        
        // make sure that websocket is actually online before trying to send any messages
        if stateStore.state.ccRequestMessagingState.webSocketState?.connectionState == .online {
            self.sendQueuedClientMessages(firstMessage: nil)
        }
    }
    
    @objc internal func sendQueuedClientMessagesTimerFiredOnce(){
        //DDLogVerbose("truncated silence period timer fired")
        sendQueuedClientMessagesTimerFired()
        
        // now we simply resume the normal timer
        DispatchQueue.main.async {self.stateStore.dispatch(ScheduleSilencePeriodTimerAction())}
    }
    
    public func sendQueuedClientMessages(firstMessage: Data?) {
        
        var workItem: DispatchWorkItem!
        
        if (firstMessage != nil){
            
            // If radioSilencer is nil, message is sent to the server instant
            if stateStore.state.ccRequestMessagingState.radiosilenceTimerState?.timeInterval == nil,
                let newMessage = firstMessage {
                
                sendMessageDirectly(message: newMessage)
                return
                
            } else {
                if let newMessage = firstMessage {
                    insertMessageInLocalDatabase(message: newMessage)
                }
            }
            
        }
        
        // inline function to get the message count and handle any errors from SQL
        let messagesCount = {() -> Int in
            
            var count:Int = -1
            
            do {
                count = try self.messagesDB.count(table: CCLocationTables.MESSAGES_TABLE)
            } catch SQLiteError.Prepare(let error) {
                Log.error("SQL Prepare Error: \(error)")
            } catch {
                Log.error("Error while executing messagesDB.count \(error)")
            }
            
            return count
        }
        
        workItem = DispatchWorkItem { [weak self] in
            
            if !workItem.isCancelled {
                
                let maxMessagesToReturn = 100
                
                var connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
                
                while (messagesCount() > 0 && connectionState == .online) {
                    
                    if workItem.isCancelled { break }
                    
                    connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
                    
                    var compiledClientMessage = Messaging_ClientMessage()
                    var backToQueueMessages = Messaging_ClientMessage()
                    
                    var tempMessageData:[Data]?
                    var subMessageCounter:Int = 0
                    var tempClientMessage:Messaging_ClientMessage?
                    
                    // inline function to get the message count and handle any errors from SQL
                    let messagesCount = {() -> Int in
                        
                        var count:Int = -1
                        
                        do {
                            if let messagesDB = self?.messagesDB {
                                count = try messagesDB.count(table: CCLocationTables.MESSAGES_TABLE)
                            }
                        } catch SQLiteError.Prepare(let error) {
                            Log.error("SQL Prepare Error: \(error)")
                        } catch {
                            Log.error("Error while executing messagesDB.count \(error)")
                        }
                        
                        return count
                    }
                    
                    if (messagesCount() == 0) {
                        Log.verbose ("No queued messages available to send")
                    }
                    
                    Log.verbose ("\(messagesCount()) Queued messages are available")
                    
                    while (messagesCount() > 0 && subMessageCounter < maxMessagesToReturn) {
                        
                        if workItem.isCancelled { break }
                        
                        tempMessageData = self?.popMessagesFromLocalDatabase(maxMessagesToReturn: maxMessagesToReturn)
                        
                        if let unwrappedTempMessageData = tempMessageData {
                            for tempMessage in unwrappedTempMessageData {
                                
                                if workItem.isCancelled { break }
                                
                                tempClientMessage = try? Messaging_ClientMessage(serializedData: tempMessage)
                                
                                if (tempClientMessage!.locationMessage.count > 0) {
                                    //                DDLogVerbose ("Found location message in queue")
                                    
                                    for tempLocationMessage in tempClientMessage!.locationMessage {
                                        
                                        var locationMessage = Messaging_LocationMessage()
                                        
                                        locationMessage.longitude = tempLocationMessage.longitude
                                        locationMessage.latitude = tempLocationMessage.latitude
                                        locationMessage.horizontalAccuracy = tempLocationMessage.horizontalAccuracy
                                        
                                        if (tempLocationMessage.hasAltitude){
                                            locationMessage.altitude = tempLocationMessage.altitude
                                        }
                                        
                                        locationMessage.timestamp = tempLocationMessage.timestamp
                                        
                                        if (subMessageCounter >= 0) {
                                            compiledClientMessage.locationMessage.append(locationMessage)
                                        } else {
                                            backToQueueMessages.locationMessage.append(locationMessage)
                                        }
                                        
                                        subMessageCounter += 1
                                    }
                                }

                                if (tempClientMessage!.step.count > 0) {
                                    Log.verbose ("Found step message in queue")
                                    
                                    for tempStepMessage in tempClientMessage!.step {
                                        
                                        var stepMessage = Messaging_Step()
                                        
                                        stepMessage.timestamp = tempStepMessage.timestamp
                                        stepMessage.angle = tempStepMessage.angle

                                        if (subMessageCounter >= 0) {
                                            compiledClientMessage.step.append(stepMessage)
                                        } else {
                                            backToQueueMessages.step.append(stepMessage)
                                        }
                                        
                                        subMessageCounter += 1
                                    }
                                }

                                if (tempClientMessage!.bluetoothMessage.count > 0) {
                                    
                                    //                DDLogVerbose ("Found bluetooth message in queue")
                                    
                                    for tempBluetoothMessage in tempClientMessage!.bluetoothMessage {
                                        
                                        var bluetoothMessage = Messaging_Bluetooth()
                                        
                                        bluetoothMessage.identifier = tempBluetoothMessage.identifier
                                        bluetoothMessage.rssi = tempBluetoothMessage.rssi
                                        bluetoothMessage.tx = tempBluetoothMessage.tx
                                        bluetoothMessage.timestamp = tempBluetoothMessage.timestamp
                                        
                                        if (subMessageCounter >= 0) {
                                            compiledClientMessage.bluetoothMessage.append(bluetoothMessage)
                                        } else {
                                            backToQueueMessages.bluetoothMessage.append(bluetoothMessage)
                                        }
                                        
                                        subMessageCounter += 1
                                    }
                                }
                                
                                if (tempClientMessage!.ibeaconMessage.count > 0) {
                                    
                                    //                DDLogVerbose ("Found ibeacon messages in queue")
                                    
                                    for tempIbeaconMessage in tempClientMessage!.ibeaconMessage {
                                        
                                        var ibeaconMessage = Messaging_IBeacon()
                                        
                                        ibeaconMessage.uuid = tempIbeaconMessage.uuid
                                        ibeaconMessage.major = tempIbeaconMessage.major
                                        ibeaconMessage.minor = tempIbeaconMessage.minor
                                        ibeaconMessage.rssi = tempIbeaconMessage.rssi
                                        ibeaconMessage.accuracy = tempIbeaconMessage.accuracy
                                        ibeaconMessage.timestamp = tempIbeaconMessage.timestamp
                                        ibeaconMessage.proximity = tempIbeaconMessage.proximity
                                        
                                        if (subMessageCounter >= 0) {
                                            compiledClientMessage.ibeaconMessage.append(ibeaconMessage)
                                        } else {
                                            backToQueueMessages.ibeaconMessage.append(ibeaconMessage)
                                        }
                                        
                                        subMessageCounter += 1
                                    }
                                }
                                
                                if (tempClientMessage!.eddystonemessage.count > 0) {
                                    
                                    //                DDLogVerbose ("Found eddystone messages in queue")
                                    
                                    for tempEddyStoneMessage in tempClientMessage!.eddystonemessage {
                                        
                                        var eddyStoneMessage = Messaging_EddystoneBeacon()
                                        
                                        eddyStoneMessage.eid = tempEddyStoneMessage.eid
                                        eddyStoneMessage.rssi = tempEddyStoneMessage.rssi
                                        eddyStoneMessage.timestamp = tempEddyStoneMessage.timestamp
                                        eddyStoneMessage.tx = tempEddyStoneMessage.tx
                                        
                                        if (subMessageCounter >= 0) {
                                            compiledClientMessage.eddystonemessage.append(eddyStoneMessage)
                                        } else {
                                            backToQueueMessages.eddystonemessage.append(eddyStoneMessage)
                                        }
                                        
                                        subMessageCounter += 1
                                    }
                                }
                                
                                
                                if (tempClientMessage!.alias.count > 0) {
                                    
                                    //                DDLogVerbose ("Found alias message in queue")
                                    
                                    for tempAliasMessage in tempClientMessage!.alias {
                                        
                                        var aliasMessage = Messaging_AliasMessage()
                                        
                                        aliasMessage.key = tempAliasMessage.key
                                        aliasMessage.value = tempAliasMessage.value
                                        
                                        if (subMessageCounter >= 0) {
                                            compiledClientMessage.alias.append(aliasMessage)
                                        } else {
                                            backToQueueMessages.alias.append(aliasMessage)
                                        }
                                        
                                        subMessageCounter += 1
                                    }
                                }
                                
                                if (tempClientMessage!.hasIosCapability){
                                    var capabilityMessage = Messaging_IosCapability()
                                    
                                    var tempCapabilityMessage = tempClientMessage!.iosCapability
                                    
                                    if tempCapabilityMessage.hasLocationServices {
                                        capabilityMessage.locationServices = tempCapabilityMessage.locationServices
                                    }
                                    
                                    if tempCapabilityMessage.hasLowPowerMode {
                                        capabilityMessage.lowPowerMode = tempCapabilityMessage.lowPowerMode
                                    }
                                    
                                    if tempCapabilityMessage.hasLocationAuthStatus {
                                        capabilityMessage.locationAuthStatus = tempCapabilityMessage.locationAuthStatus
                                    }
                                    
                                    if tempCapabilityMessage.hasBluetoothHardware {
                                        capabilityMessage.bluetoothHardware = tempCapabilityMessage.bluetoothHardware
                                    }
                                    
                                    if tempCapabilityMessage.hasBatteryState {
                                        capabilityMessage.batteryState = tempCapabilityMessage.batteryState
                                    }
                                    
                                    if (subMessageCounter >= 0) {
                                        compiledClientMessage.iosCapability = capabilityMessage
                                    } else {
                                        backToQueueMessages.iosCapability = capabilityMessage
                                    }
                                    
                                    subMessageCounter += 1
                                }
                                
                                if (tempClientMessage!.hasMarker){
                                    
                                    //                DDLogVerbose("Found marker message in queue");
                                    
                                    var markerMessage = Messaging_MarkerMessage()
                                    
                                    markerMessage.data = tempClientMessage!.marker.data
                                    markerMessage.time = tempClientMessage!.marker.time
                                    
                                    compiledClientMessage.marker = markerMessage
                                    
                                    subMessageCounter += 1
                                }
                            }
                        }
                    }
                    
                    //DDLogVerbose("Compiled \(subMessageCounter) message(s)")
                    
                    //        if (compiledClientMessage.locationMessage.count > 0){
                    //            let geoMsg = compiledClientMessage.locationMessage[0]
                    //            let geoData = try? geoMsg.serializedData()
                    //DDLogVerbose("compiled geoMsg: \(geoData?.count ?? -1) and byte array: \(geoData?.hexEncodedString() ?? "NOT AVAILABLE")")
                    //        }
                    
                    //        if (compiledClientMessage.bluetoothMessage.count > 0){
                    //            let blMsg = compiledClientMessage.bluetoothMessage[0]
                    //            let blData = try? blMsg.serializedData()
                    //DDLogVerbose("compiled bluetooth message: \(blData?.count ?? -1) and byte array: \(blData?.hexEncodedString() ?? "NOT AVAILABLE"))")
                    
                    //        }
                    
                    //        for beacon in compiledClientMessage.ibeaconMessage {
                    //            DDLogVerbose("Sending beacons \(compiledClientMessage.ibeaconMessage.count) with \(beacon)")
                    //        }
                    
                    //        if (compiledClientMessage.alias.count > 0){
                    //            let alMsg = compiledClientMessage.alias[0]
                    //            let alData = try? alMsg.serializedData()
                    //DDLogVerbose("compiled alias message: \(alData?.count ?? -1)  and byte array: \(alData?.hexEncodedString() ?? "NOT AVAILABLE"))")
                    //        }
                    
                    if workItem.isCancelled { break }
                    
                    if let backToQueueData = try? backToQueueMessages.serializedData() {
                        //DDLogDebug("Had to split a client message into two, pushing \(subMessageCounter) unsent messages back to the Queue")
                        if backToQueueData.count > 0 {
                            //    ccRequest?.messageQueuePushSwiftBridge(backToQueueData)
                            
                            self?.insertMessageInLocalDatabase(message: backToQueueData)
                        }
                    } else {
                        //DDLogError("Couldn't serialize back to queue data")
                    }
                    
                    if let isNewBatteryLevel = self?.stateStore.state.batteryLevelState.isNewBatteryLevel {
                        if isNewBatteryLevel {
                            var batteryMessage = Messaging_Battery()
                            
                            if let batteryLevel = self?.stateStore.state.batteryLevelState.batteryLevel {
                                batteryMessage.battery = batteryLevel
                                compiledClientMessage.battery = batteryMessage
                                DispatchQueue.main.async {self?.stateStore.dispatch(BatteryLevelReportedAction())}
                                //                DDLogVerbose("Battery message build: \(batteryMessage)")
                            }
                        }
                    }
                    
                    if let data = try? compiledClientMessage.serializedData(){
                        if (data.count > 0) {
                            
                            if let stateStore = self?.stateStore {
                                if let ccSocket = self?.ccSocket {
                                    if let isRebootTimeSame = self?.timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket) {
                                        if isRebootTimeSame {
                                            if let currentTimePeriod = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                                                compiledClientMessage.sentTime = UInt64(currentTimePeriod * 1000)
                                                //                        DDLogVerbose("Added sent time to the client message")
                                            }
                                        }
                                    }
                                    
                                    if let dataIncludingSentTime = try? compiledClientMessage.serializedData(){
                                        //            Log.verbose("Sending \(unwrappedData.count) bytes of compiled client message data")
                                        self?.ccSocket?.sendWebSocketMessage(data: dataIncludingSentTime)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if let index = self?.workItems.index(where: {$0 === workItem!}) {
                    self?.workItems.remove(at: index)
                }
                
                workItem = nil
            }
        }
        
        workItems.append(workItem)
        
        DispatchQueue.global(qos: .background).async(execute: workItem)
    }
    
    // MARK: - APPLICATION STATE HANDLING FUNCTIONS
    
    @objc func applicationWillResignActive () {
        //        DDLogDebug("[APP STATE] applicationWillResignActive");
    }
    
    @objc func applicationDidEnterBackground () {
        
        //        DDLogDebug("[APP STATE] applicationDidEnterBackground");
        
        DispatchQueue.main.async {self.stateStore.dispatch(LifeCycleAction(lifecycleState: LifeCycle.background))}
    }
    
    @objc func applicationWillEnterForeground () {
        //        DDLogDebug("[APP STATE] applicationWillEnterForeground");
        
    }
    
    @objc func applicationDidBecomeActive () {
        //        DDLogDebug("[APP STATE] applicationDidBecomeActive");
        
        DispatchQueue.main.async {self.stateStore.dispatch(LifeCycleAction(lifecycleState: LifeCycle.foreground))}
    }
    
    @objc func applicationWillTerminate () {
        //        DDLogDebug("[APP STATE] applicationWillTerminate");
    }
    
    // MARK:- SYSTEM NOTIFCATIONS SETUP
    
    func setupApplicationNotifications () {
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(applicationWillResignActive),
                                               name:UIApplication.willResignActiveNotification,
                                               object:nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(applicationDidEnterBackground),
                                               name:UIApplication.didEnterBackgroundNotification,
                                               object:nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(applicationWillEnterForeground),
                                               name:UIApplication.willEnterForegroundNotification,
                                               object:nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(applicationDidBecomeActive),
                                               name:UIApplication.didBecomeActiveNotification,
                                               object:nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(applicationWillTerminate),
                                               name:UIApplication.willTerminateNotification,
                                               object:nil)
    }
    
    
    
    func setupBatteryStateAndLevelNotifcations (){
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(batteryLevelDidChange), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(batteryStateDidChange), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        
        //        if #available(iOS 9.0, *) {
        //            NotificationCenter.default.addObserver(self, selector: #selector(powerModeDidChange), name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        //        }
    }
    
    func version() -> String {
        let dictionary = Bundle.main.infoDictionary!
        let version = dictionary["CFBundleShortVersionString"] as! String
        let build = dictionary["CFBundleVersion"] as! String
        return "\(version) build \(build)"
    }
    
    @objc func batteryLevelDidChange(notification: Notification){
        let batteryLevel = UIDevice.current.batteryLevel
        
        DispatchQueue.main.async {self.stateStore.dispatch(BatteryLevelChangedAction(batteryLevel: UInt32(batteryLevel * 100)))}
    }
    
    @objc func batteryStateDidChange(notification: Notification){
        let batteryState = UIDevice.current.batteryState
        
        DispatchQueue.main.async {self.stateStore.dispatch(BatteryStateChangedAction(batteryState: batteryState))}
    }
    
    func powerModeDidChange(notification: Notification) {
        if #available(iOS 9.0, *) {
            let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            
            DispatchQueue.main.async {self.stateStore.dispatch(IsLowPowerModeEnabledAction(isLowPowerModeEnabled: isLowPowerMode))}
        }
    }
    
    func stop () {
        NotificationCenter.default.removeObserver(self)
        stateStore.unsubscribe(self)
        killTimeBetweenSendsTimer()
        
        timeHandling.delegate = nil
        
        for workItem in workItems {
            workItem.cancel()
            Log.verbose("Cancelling work item")
        }
        
        workItems.removeAll()
        
        messagesDB.close()
        messagesDB = nil
    }
    
    func killTimeBetweenSendsTimer() {
        if timeBetweenSendsTimer != nil {
            timeBetweenSendsTimer?.invalidate()
            timeBetweenSendsTimer = nil
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        //        DDLogVerbose("CCRequestMessaging DEINIT")
        //        if #available(iOS 10.0, *) {
        //            os_log("[CC] CCRequestMessaging DEINIT")
        //        } else {
        //            // Fallback on earlier versions
        //        }
    }
}

// MARK:- TimeHandling delegate
extension CCRequestMessaging: TimeHandlingDelegate {
    public func newTrueTimeAvailable(trueTime: Date, timeIntervalSinceBootTime: TimeInterval, systemTime: Date, lastRebootTime: Date) {
        Log.debug("received new truetime \(trueTime), timeIntervalSinceBootTime \(timeIntervalSinceBootTime), systemTime \(systemTime), lastRebootTime \(lastRebootTime)")
        
        DispatchQueue.main.async {self.stateStore.dispatch(NewTruetimeReceivedAction(lastTrueTime: trueTime, bootTimeIntervalAtLastTrueTime: timeIntervalSinceBootTime, systemTimeAtLastTrueTime: systemTime, lastRebootTime: lastRebootTime))}
        
        if let radioSilenceTimerState = stateStore.state.ccRequestMessagingState.radiosilenceTimerState {
            if (radioSilenceTimerState.timer == .stopped){
                if radioSilenceTimerState.startTimeInterval != nil {
                    DispatchQueue.main.async {self.stateStore.dispatch(ScheduleSilencePeriodTimerAction())}
                }
            }
        }
    }
}

// MARK:- StoreSubscriber delegate
extension CCRequestMessaging: StoreSubscriber {
    public func newState(state: CCRequestMessagingState) {
        
        //DDLogDebug("new state is: \(state)")
        
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
        
        // if we have a radioSilenceTimer
        if let newTimerState = state.radiosilenceTimerState {
            
            // and if its state has changed
            if newTimerState != currentRadioSilenceTimerState {
                
                currentRadioSilenceTimerState = newTimerState
                
                if newTimerState.timer == .schedule {
                    
                    if let timeInterval = newTimerState.timeInterval {
                        
                        //                        DDLogVerbose("RADIOSILENCETIMER trying to schedule timer with timeInterval = \(timeInterval / 1000)")
                        
                        if timeBetweenSendsTimer != nil {
                            if timeBetweenSendsTimer!.isValid{
                                timeBetweenSendsTimer!.invalidate()
                            }
                        }
                        
                        if let radioSilenceTimerState = newTimerState.startTimeInterval {
                            
                            let intervalForLastTimer = TimeHandling.timeIntervalSinceBoot() - radioSilenceTimerState
                            
                            //                            DDLogVerbose("RADIOSILENCETIMER intervalForLastTimer = \(intervalForLastTimer)")
                            
                            if intervalForLastTimer < Double(Double(timeInterval) / 1000) {
                                timeBetweenSendsTimer = Timer.scheduledTimer(timeInterval:TimeInterval(intervalForLastTimer), target: self, selector: #selector(self.sendQueuedClientMessagesTimerFiredOnce), userInfo: nil, repeats: false)
                                DispatchQueue.main.async {self.stateStore.dispatch(TimerRunningAction(startTimeInterval: nil))}
                            } else {
                                timeBetweenSendsTimer = Timer.scheduledTimer(timeInterval:TimeInterval(Double(timeInterval) / 1000), target: self, selector: #selector(self.sendQueuedClientMessagesTimerFired), userInfo: nil, repeats: true)
                                
                                DispatchQueue.main.async {self.stateStore.dispatch(TimerRunningAction(startTimeInterval: TimeHandling.timeIntervalSinceBoot()))}
                            }
                            
                        } else {
                            
                            timeBetweenSendsTimer = Timer.scheduledTimer(timeInterval:TimeInterval(Double(timeInterval) / 1000), target: self, selector: #selector(self.sendQueuedClientMessagesTimerFired), userInfo: nil, repeats: true)
                            
                            DispatchQueue.main.async {self.stateStore.dispatch(TimerRunningAction(startTimeInterval: TimeHandling.timeIntervalSinceBoot()))}
                        }
                    }
                }
                
                if newTimerState.timer == .running {
                    //                    DDLogVerbose("RADIOSILENCETIMER timer is in running state")
                }
                
                // covers case were app starts from terminated and no timer is available yet
                if timeBetweenSendsTimer == nil {
                    //                    DDLogVerbose("RADIOSILENCETIMER timeBetweenSendsTimer == nil, scheduling new timer")
                    if timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket){
                        DispatchQueue.main.async {self.stateStore.dispatch(ScheduleSilencePeriodTimerAction())}
                    }
                }
                
                if newTimerState.timer == .invalidate {
                    
                    //                    DDLogVerbose("RADIOSILENCETIMER invalidate timer")
                    
                    if timeBetweenSendsTimer != nil{
                        if timeBetweenSendsTimer!.isValid {
                            timeBetweenSendsTimer!.invalidate()
                        }
                        timeBetweenSendsTimer = nil
                    }
                    
                    DispatchQueue.main.async {self.stateStore.dispatch(TimerStoppedAction())}
                }
            }
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
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

extension Sequence {
    func group<U: Hashable>(by key: (Iterator.Element) -> U) -> [U:[Iterator.Element]] {
        var categories: [U: [Iterator.Element]] = [:]
        for element in self {
            let key = key(element)
            if case nil = categories[key]?.append(element) {
                categories[key] = [element]
            }
        }
        return categories
    }
}
