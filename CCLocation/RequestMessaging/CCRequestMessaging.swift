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
    
    enum MessageType {
        case queueable     // if radioSilence is not 0 or null, will be added in the database and send next time
        case discardable   // will be sent directly regardless radioSilence value (alongside with all the other messages) if there is connection, otherwise, will be deleted
        case urgent        // will be sent alone immediately regardless radioSilence value it there is connection, otherwise will be saved in the database
    }
    
    weak var ccSocket: CCSocket?
    @Atomic var stateStore: Store<LibraryState>?
    weak var timeHandling: TimeHandling!
    
    var currentRadioSilenceTimerState: TimerState?
    var currentWebSocketState: WebSocketState?
    var currentLibraryTimerState: LibraryTimeState?
    var currentCapabilityState: CapabilityState?
    
    weak var timeBetweenSendsTimer: Timer?
    
    internal var messagesDB: SQLiteDatabase!
    internal let messagesDBName = "observations.db"
    
    var surveyMode: Bool = false
    
    init(ccSocket: CCSocket, stateStore: Store<LibraryState>) {
        super.init()
        
        self.ccSocket = ccSocket
        self.stateStore = stateStore
        
        timeHandling = TimeHandling.shared
        timeHandling.delegate = self
        
        self.stateStore?.subscribe(self) {
            $0.select {
                state in state.ccRequestMessagingState
            }
        }
        
        if stateStore.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime == nil {
            timeHandling.fetchTrueTime()
        }
        
        openMessagesDatabase()
        createCCMesageTable()
        
        setupApplicationNotifications()
        setupBatteryStateAndLevelNotifcations()
        
        //initial dispatch of battery state
        batteryStateDidChange(notification: Notification(name: UIDevice.batteryStateDidChangeNotification))
    }

    // MARK: ACCESS STATE STORE

    func getStateConnectionState() -> ConnectionState? {
        stateStore?.state.ccRequestMessagingState.webSocketState?.connectionState
    }

    func getStateTimeBetweenSendings() -> UInt64? {
        stateStore?.state.ccRequestMessagingState.radiosilenceTimerState?.timeInterval
    }

    func getStateLastTrueTime() -> Date? {
        stateStore?.state.ccRequestMessagingState.libraryTimeState?.lastTrueTime
    }

    func getStateRadioSilenceTimerState() -> TimerState? {
        stateStore?.state.ccRequestMessagingState.radiosilenceTimerState
    }

    // MARK: - PROCESS RECEIVED COLOCATOR SERVER MESSAGES FUNCTIONS
    
    public func processServerMessage(data: Data) throws {
        let serverMessage = try Messaging_ServerMessage.init(serializedData: data)
        
        let serverMessageJSON = try serverMessage.jsonString()
        if serverMessageJSON.count > 2 {
            Log.info("[Colocator] Received message from server \n\(serverMessage)")
        }
        
        // The message coming from the server can be either a location update, a set of settings or an empty message
        // The empty message is ignored
        // The location update is converted in a LocationReponse object and sent to the delegate fo the library
        // The settings are analysed separately (global and ios settings), stored locally and the library state si updated to match them

        if stateStore != nil {
            processGlobalSettings(serverMessage: serverMessage, store: stateStore!)
            processIosSettings(serverMessage: serverMessage, store: stateStore!)
        }

        processLocationResponseMessages(serverMessage: serverMessage)
    }
    
    func processLocationResponseMessages(serverMessage: Messaging_ServerMessage) {
        if !serverMessage.locationResponses.isEmpty {
            var messages: [LocationResponse] = []
            
            for locationResponse in serverMessage.locationResponses {
                let newLocationMessage = LocationResponse(latitude: locationResponse.latitude,
                                                          longitude: locationResponse.longitude,
                                                          headingOffSet: locationResponse.headingOffset,
                                                          error: locationResponse.error,
                                                          timestamp: locationResponse.timestamp,
                                                          floor: locationResponse.floor)
                
                messages.append(newLocationMessage)
            }
            ccSocket?.delegate?.receivedLocationMessages(messages)
        }
    }
    
    func processGlobalSettings(serverMessage: Messaging_ServerMessage, store: Store<LibraryState>) {
        if serverMessage.hasGlobalSettings {
            Log.debug("Got global settings message")
            
            let globalSettings = serverMessage.globalSettings
            var radioSilence: UInt64? = nil
            
            // if radio silence is 0, treat it as missing - continuous data flow
            if globalSettings.hasRadioSilence && globalSettings.radioSilence != 0 {
                radioSilence = globalSettings.radioSilence
            }
            
            DispatchQueue.main.async {
                store.dispatch(TimeBetweenSendsTimerReceivedAction(timeInMilliseconds: radioSilence))
            }
            
            if globalSettings.hasID {
                let uuid = NSUUID(uuidBytes: ([UInt8](globalSettings.id)))
                ccSocket?.setDeviceId(deviceId: uuid.uuidString)
            }
        }
    }
    
    // Capabilities are reported to the server when the connection is established and when at least one of them is changed
    // Be it a permission, a module state or device's battery state
    public func processIOSCapability(locationAuthStatus: CLAuthorizationStatus?,
                                     locationAccuracyStatus: CLAccuracyAuthorization?,
                                     bluetoothHardware: CBCentralManagerState?,
                                     batteryState: UIDevice.BatteryState?,
                                     isLowPowerModeEnabled: Bool?,
                                     isLocationServicesEnabled: Bool?,
                                     isMotionAndFitnessEnabled: Bool?){
        var clientMessage = Messaging_ClientMessage()
        var capabilityMessage = Messaging_IosCapability()
        
        if let locationServices = isLocationServicesEnabled {
            capabilityMessage.locationServices = locationServices
        }
        if let motionServices = isMotionAndFitnessEnabled {
            capabilityMessage.motionAndFitness = motionServices
        }
        if let lowPowerMode = isLowPowerModeEnabled {
            capabilityMessage.lowPowerMode = lowPowerMode
        }
        if let locationAuthStatus = locationAuthStatus {
            capabilityMessage.locationAuthStatus = getLocationAuthStatus(forAuthorisationStatus: locationAuthStatus)
        }
        if let locationAccuracyStatus = locationAccuracyStatus {
            capabilityMessage.accuracyStatus = getLocationAccuracyStatus(forAccuracyStatus: locationAccuracyStatus)
        }
        if let bluetoothHardware = bluetoothHardware {
            capabilityMessage.bluetoothHardware = getBluetoothStatus(forBluetoothState: bluetoothHardware)
        }
        if let batteryState = batteryState {
            capabilityMessage.batteryState = getBatteryState(fromState: batteryState)
        }
        
        clientMessage.iosCapability = capabilityMessage
        
        if let data = try? clientMessage.serializedData() {
            Log.debug("Capability message built\n\(clientMessage)")
            sendOrQueueClientMessage(data: data, messageType: .queueable)
        }
    }
    
    // MARK: - STATE HANDLING FUNCTIONS
    
    public func webSocketDidOpen() {
        DispatchQueue.main.async { [weak self] in
            self?.stateStore?.dispatch(WebSocketAction(connectionState: ConnectionState.online))
        }
    }
    
    public func webSocketDidClose() {
        DispatchQueue.main.async { [weak self] in
            self?.stateStore?.dispatch(WebSocketAction(connectionState: ConnectionState.offline))
        }
    }
    
    // MARK: - HIGH LEVEL SEND CLIENT MESSAGE DATA
    
    func sendOrQueueClientMessage(data: Data, messageType: MessageType) {
        let connectionState = getStateConnectionState()
        let timeBetweenSends = getStateTimeBetweenSendings()
        
        sendOrQueueClientMessage(data: data,
                                 messageType: messageType,
                                 connectionState: connectionState,
                                 timeBetweenSends: timeBetweenSends)
    }

    // Check the connection state, radioSilence, message type and handle the new data properly
    // It can be even sent to the server, stored in the database or discarded
    func sendOrQueueClientMessage(data: Data, messageType: MessageType, connectionState: ConnectionState?, timeBetweenSends: UInt64?) {
        if let connectionStateUnwrapped = connectionState, connectionStateUnwrapped == .online {
            
            if timeBetweenSends == nil || timeBetweenSends == 0 {
                Log.verbose("Websocket open, buffer timer absent, send new and queued messages")
                self.sendQueuedClientMessages(firstMessage: data)
            } else {
                if messageType == .queueable {
                    Log.verbose("Message queuable, buffer timer present, queue message")
                    insertMessageInLocalDatabase(message: data)
                }
                if messageType == .discardable {
                    Log.verbose("Websocket online, buffer timer present, message discardable, send new and queued messages")
                    sendQueuedClientMessages(firstMessage: data)
                }
                if messageType == .urgent {
                    Log.verbose("Websocket online, buffer timer present,  urgent message, send current messages")
                    sendSingleMessage(data)
                }
            }
        } else {
            if messageType == .queueable {
                Log.verbose("Websocket offline, message queuable, queue message")
                insertMessageInLocalDatabase(message: data)
            }
            if messageType == .discardable {
                Log.verbose("Websocket offline, message discardable, discard message")
            }
            if messageType == .urgent {
                Log.verbose("Websocket offline, urgent message , add into database")
                insertMessageInLocalDatabase(message: data)
            }
        }
    }
    
    // sendQueuedClientMessage for timeBetweenSendsTimer firing
    @objc internal func sendQueuedClientMessagesTimerFired() {
        Log.verbose("Flushing queued messages")

        if getStateConnectionState() == .online {
            sendQueuedClientMessages(firstMessage: nil)
        }
    }
    
    func sendQueuedMessagesAndStopTimer() {
        if getStateConnectionState() == .online {
            sendQueuedClientMessages(firstMessage: nil)
        }

        timeBetweenSendsTimer?.invalidate()
        timeBetweenSendsTimer = nil
    }
    
    @objc internal func sendQueuedClientMessagesTimerFiredOnce() {
        Log.verbose("Truncated silence period timer fired")
        sendQueuedClientMessagesTimerFired()
        
        // now we simply resume the normal timer
        DispatchQueue.main.async { [weak self] in
            self?.stateStore?.dispatch(ScheduleSilencePeriodTimerAction())
        }
    }
    
    func stop() {
        Log.info("[Colocator] Stopping RequestMessaging ...")
        NotificationCenter.default.removeObserver(self)

        killTimeBetweenSendsTimer()
        timeHandling.delegate = nil
        
        messagesDB.close()
        messagesDB = nil
    }
    
    func killTimeBetweenSendsTimer() {
        timeBetweenSendsTimer?.invalidate()
        timeBetweenSendsTimer = nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)

        Log.info("Deinitialize CCRequestMessaging")
    }
}

// MARK:- TimeHandling delegate

extension CCRequestMessaging: TimeHandlingDelegate {
    
    // For avoiding using a wrong timestamp (local device time) and having a uniform timezone over all the devices
    // TrueTime library is used and every message reported contains the true timestamp, not the local one
    public func newTrueTimeAvailable(trueTime: Date, timeIntervalSinceBootTime: TimeInterval, systemTime: Date, lastRebootTime: Date) {
        Log.debug("""
            Received new truetime \(trueTime)
            TimeIntervalSinceBootTime \(timeIntervalSinceBootTime)
            SystemTime \(systemTime)
            LastRebootTime \(lastRebootTime)
            """)
        
        DispatchQueue.main.async { [weak self] in
            self?.stateStore?.dispatch(NewTruetimeReceivedAction(lastTrueTime: trueTime,
                                                                bootTimeIntervalAtLastTrueTime: timeIntervalSinceBootTime,
                                                                systemTimeAtLastTrueTime: systemTime,
                                                                lastRebootTime: lastRebootTime))
        }
        
        guard let radioSilenceTimerState = getStateRadioSilenceTimerState() else {
            return
        }
        
        if radioSilenceTimerState.timer == .stopped && radioSilenceTimerState.startTimeInterval != nil {
            DispatchQueue.main.async { [weak self] in
                self?.stateStore?.dispatch(ScheduleSilencePeriodTimerAction())
            }
        }
    }
}
