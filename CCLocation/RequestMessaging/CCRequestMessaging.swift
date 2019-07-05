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
import CoreBluetooth

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
        Log.info("\(serverMessage)")
        
        processGlobalSettings(serverMessage: serverMessage, store: stateStore)
        processIosSettings(serverMessage: serverMessage, store: stateStore)
        
        //        processBTSettings(serverMessage: serverMessage)
        //        processSystemBeacons(serverMessage: serverMessage)
        //        [self processTextMessageWrapper:serverMessage];
    }
    
    func processGlobalSettings(serverMessage:Messaging_ServerMessage, store: Store<LibraryState>) {
        
        if (serverMessage.hasGlobalSettings) {
            Log.debug("Got global settings message")
            
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
    
    //    func processSystemBeacons(serverMessage:Messaging_ServerMessage) {
    //
    //        if (serverMessage.beacon.count > 0) {
    //            Log.debug("Got an iBeacon message")
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
    //            Log.debug("got BT settings")
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
    //        Log.verbose ("Collated Bluetooth message build: \(clientMessage)")
    //
    //        if let data = try? clientMessage.serializedData(){
    //            sendClientMessage(data: data, messageType: .queueable)
    //        }
    //    }
    
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
            Log.debug("Capability message build: \(clientMessage) with size: \(String(describing: data.count))")
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
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
                        Log.verbose("Message is queuable, buffer timer active, going to queue message")
                        
                        insertMessageInLocalDatabase(message: data)
                    }
                    
                    // case for Latency Message, when buffer timer is set
                    if (messageType == .discardable){
                        Log.verbose("Message is discardable (most likely latency message), buffer timer active, Websocket is online, sending new and queued messages")
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
            Log.verbose("Websocket is offline, message is queuable, going to queue message")
            insertMessageInLocalDatabase(message: data)
        }
        
        // case for Latency message, when offline
        if (messageType == .discardable){
            Log.verbose("Websocket offline, message discardable, going to discard message")
        }
    }
    
    // sendQueuedClientMessage for timeBetweenSendsTimer firing
    @objc internal func sendQueuedClientMessagesTimerFired(){
        Log.info("Flushing queued messages")
        
        // make sure that websocket is actually online before trying to send any messages
        if stateStore.state.ccRequestMessagingState.webSocketState?.connectionState == .online {
            self.sendQueuedClientMessages(firstMessage: nil)
        }
    }
    
    @objc internal func sendQueuedClientMessagesTimerFiredOnce(){
        Log.verbose("Truncated silence period timer fired")
        sendQueuedClientMessagesTimerFired()
        
        // now we simply resume the normal timer
        DispatchQueue.main.async {self.stateStore.dispatch(ScheduleSilencePeriodTimerAction())}
    }
    
    // MARK: - APPLICATION STATE HANDLING FUNCTIONS
    
    @objc func applicationWillResignActive () {
        Log.debug("[APP STATE] applicationWillResignActive");
    }
    
    @objc func applicationDidEnterBackground () {
        Log.debug("[APP STATE] applicationDidEnterBackground");
        
        DispatchQueue.main.async {self.stateStore.dispatch(LifeCycleAction(lifecycleState: LifeCycle.background))}
    }
    
    @objc func applicationWillEnterForeground () {
        Log.debug("[APP STATE] applicationWillEnterForeground");
    }
    
    @objc func applicationDidBecomeActive () {
        Log.debug("[APP STATE] applicationDidBecomeActive");
        
        DispatchQueue.main.async {self.stateStore.dispatch(LifeCycleAction(lifecycleState: LifeCycle.foreground))}
    }
    
    @objc func applicationWillTerminate () {
        Log.debug("[APP STATE] applicationWillTerminate");
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
        Log.debug("CCRequestMessaging DEINIT")
        if #available(iOS 10.0, *) {
            Log.debug("[CC] CCRequestMessaging DEINIT")
        } else {
            // Fallback on earlier versions
        }
    }
}

// MARK:- TimeHandling delegate
extension CCRequestMessaging: TimeHandlingDelegate {
    public func newTrueTimeAvailable(trueTime: Date, timeIntervalSinceBootTime: TimeInterval, systemTime: Date, lastRebootTime: Date) {
        Log.debug("Received new truetime \(trueTime), timeIntervalSinceBootTime \(timeIntervalSinceBootTime), systemTime \(systemTime), lastRebootTime \(lastRebootTime)")
        
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
