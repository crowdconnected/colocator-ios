//
//  CCRequestMessaging+SendMessages.swift
//  CCLocation
//
//  Created by Mobile Developer on 03/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import Foundation

// Extension Send Messages

extension CCRequestMessaging {
    
    public func sendMessageDirectly(message: Data) {
        
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem { [weak self] in
            
            if workItem.isCancelled { return }
            
            let connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
            
            if connectionState != .online {
                Log.verbose("Connection offline. Instant message inserted in db")
                
                self?.insertMessageInLocalDatabase(message: message)
            }
            
            if self == nil {
                //This should not happen
                Log.error("Self object is nil inside sending message method. Message won't be delivered or queued")
                return
            }
            
            var (_, compiledClientMessage, backToQueueMessage) = self?.handleMessageType(message: message) ?? (0, Messaging_ClientMessage(),Messaging_ClientMessage())
            
            if let backToQueueData = try? backToQueueMessage.serializedData() {
                //DDLogDebug("Had to split a client message into two, pushing \(subMessageCounter) unsent messages back to the Queue")
                if backToQueueData.count > 0 {
                    //    ccRequest?.messageQueuePushSwiftBridge(backToQueueData)
                    
                    self?.insertMessageInLocalDatabase(message: backToQueueData)
                }
            } else {
                //DDLogError("Couldn't serialize back to queue data")
            }
            
            if let data = try? compiledClientMessage.serializedData(){
                if (data.count > 0) {
                    if let stateStore = self?.stateStore,
                         let ccSocket = self?.ccSocket {
                        if let isRebootTimeSame = self?.timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket) {
                            if isRebootTimeSame {
                                if let currentTimePeriod = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                                    compiledClientMessage.sentTime = UInt64(currentTimePeriod * 1000)
                                }
                            }
                        }
                        
                        if let dataIncludingSentTime = try? compiledClientMessage.serializedData(){
                            self?.ccSocket?.sendWebSocketMessage(data: dataIncludingSentTime)
                            
                            Log.verbose("Instant message sent to server")
                        }
                    }
                }
            }
        }
        
        DispatchQueue.global(qos: .background).async(execute: workItem)
    }
    
    // MARK: - ANALYZE MESSAGE AND ITS TYPE
    
    public func handleMessageType(message: Data,
                                  subMessageInitialNumber: Int = 0,
                                  compiledMessage: Messaging_ClientMessage = Messaging_ClientMessage(),
                                  queueMessage: Messaging_ClientMessage = Messaging_ClientMessage()) -> (Int, Messaging_ClientMessage, Messaging_ClientMessage) {
        
        var compiledClientMessage = compiledMessage
        var backToQueueMessages = queueMessage
        
        var subMessageCounter: Int = subMessageInitialNumber
        var tempClientMessage: Messaging_ClientMessage?
        
        tempClientMessage = try? Messaging_ClientMessage(serializedData: message)
        
        if (tempClientMessage!.locationMessage.count > 0) {
             //                DDLogVerbose ("Found location messages in queue")
            
            let (actualizedSubmessageCounter, toCompileMessages, toQueueMessages) = self.checkLocationTypeMessages(tempClientMessage!.locationMessage, subMessageCounter: subMessageCounter)
            
            subMessageCounter = actualizedSubmessageCounter
            compiledClientMessage.locationMessage.append(contentsOf: toCompileMessages)
            backToQueueMessages.locationMessage.append(contentsOf: toQueueMessages)
        }
        
        if (tempClientMessage!.step.count > 0) {
             //                DDLogVerbose ("Found step messages in queue")
            
            let (actualizedSubmessageCounter, toCompileMessages, toQueueMessages) = self.checkStepsTypeMessages(tempClientMessage!.step, subMessageCounter: subMessageCounter)
            
            subMessageCounter = actualizedSubmessageCounter
            compiledClientMessage.step.append(contentsOf: toCompileMessages)
            backToQueueMessages.step.append(contentsOf: toQueueMessages)
        }
        
        if (tempClientMessage!.bluetoothMessage.count > 0) {
             //                DDLogVerbose ("Found bluetooth messages in queue")
            
            let (actualizedSubmessageCounter, toCompileMessages, toQueueMessages) = self.checkBluetoothTypeMessages(tempClientMessage!.bluetoothMessage, subMessageCounter: subMessageCounter)
            
            subMessageCounter = actualizedSubmessageCounter
            compiledClientMessage.bluetoothMessage.append(contentsOf: toCompileMessages)
            backToQueueMessages.bluetoothMessage.append(contentsOf: toQueueMessages)
        }
        
        if (tempClientMessage!.ibeaconMessage.count > 0) {
             //                DDLogVerbose ("Found ibeacon messages in queue")
            
            let (actualizedSubmessageCounter, toCompileMessages, toQueueMessages) = self.checkiBeaconTypeMessages(tempClientMessage!.ibeaconMessage, subMessageCounter: subMessageCounter)
            
            subMessageCounter = actualizedSubmessageCounter
            compiledClientMessage.ibeaconMessage.append(contentsOf: toCompileMessages)
            backToQueueMessages.ibeaconMessage.append(contentsOf: toQueueMessages)
        }
        
        if (tempClientMessage!.eddystonemessage.count > 0) {
             //                DDLogVerbose ("Found eddystone messages in queue")
            
            let (actualizedSubmessageCounter, toCompileMessages, toQueueMessages) = self.checkEddystoneTypeMessages(tempClientMessage!.eddystonemessage, subMessageCounter: subMessageCounter)
            
            subMessageCounter = actualizedSubmessageCounter
            compiledClientMessage.eddystonemessage.append(contentsOf: toCompileMessages)
            backToQueueMessages.eddystonemessage.append(contentsOf: toQueueMessages)
        }
        
        
        if (tempClientMessage!.alias.count > 0) {
             //                DDLogVerbose ("Found alias messages in queue")
            
            let (actualizedSubmessageCounter, toCompileMessages, toQueueMessages) = self.checkAliasesTypeMessages(tempClientMessage!.alias, subMessageCounter: subMessageCounter)
            
            subMessageCounter = actualizedSubmessageCounter
            compiledClientMessage.alias.append(contentsOf: toCompileMessages)
            backToQueueMessages.alias.append(contentsOf: toQueueMessages)
        }
        
        if (tempClientMessage!.hasIosCapability){
             //                DDLogVerbose ("Found iosCapability messages in queue")
            
            let (actualizedSubmessageCounter, toCompileMessage, toQueueMessage) = self.checkMessageIOSCapability(tempClientMessage!.iosCapability, subMessageCounter: subMessageCounter)
            
            subMessageCounter = actualizedSubmessageCounter
            if let newCompileMessage = toCompileMessage {
                compiledClientMessage.iosCapability = newCompileMessage
            }
            if let newQueueMessage = toQueueMessage {
                backToQueueMessages.iosCapability = newQueueMessage
            }
        }
        
        let (actualizedSubmessageCounter, toCompileMessage) = self.checkMarkerMessage(tempClientMessage!, subMessageCounter: subMessageCounter)
        subMessageCounter = actualizedSubmessageCounter
        if let newCompileMessage = toCompileMessage {
             //                DDLogVerbose ("Found marker messages in queue")
            compiledClientMessage.marker = newCompileMessage
        }
        
        if let newBatteryMessage = self.checkNewBatteryLevelTypeMessage() {
             //                DDLogVerbose ("Found new battery level messages in queue")
            compiledClientMessage.battery = newBatteryMessage
        }
        
        return (subMessageCounter, compiledClientMessage, backToQueueMessages)
    }
    
    public func checkLocationTypeMessages(_ messages: [Messaging_LocationMessage],
                                          subMessageCounter: Int) -> (Int, [Messaging_LocationMessage], [Messaging_LocationMessage]) {
    
        var clientMessagesToCompile = [Messaging_LocationMessage]()
        var messagesToQueue = [Messaging_LocationMessage]()
        var subMessageNo = subMessageCounter
        
        for tempLocationMessage in messages {
        
            var locationMessage = Messaging_LocationMessage()
        
            locationMessage.longitude = tempLocationMessage.longitude
            locationMessage.latitude = tempLocationMessage.latitude
            locationMessage.horizontalAccuracy = tempLocationMessage.horizontalAccuracy
        
            if (tempLocationMessage.hasAltitude){
                locationMessage.altitude = tempLocationMessage.altitude
            }
        
            locationMessage.timestamp = tempLocationMessage.timestamp
        
            if (subMessageNo >= 0) {
                clientMessagesToCompile.append(locationMessage)
            } else {
                messagesToQueue.append(locationMessage)
            }
        
            subMessageNo += 1
        }
    
        return (subMessageNo, clientMessagesToCompile, messagesToQueue)
    }
    
    public func checkStepsTypeMessages(_ messages: [Messaging_Step],
                                       subMessageCounter: Int) -> (Int, [Messaging_Step], [Messaging_Step]) {
        var clientMessagesToCompile = [Messaging_Step]()
        var messagesToQueue = [Messaging_Step]()
        var subMessageNo = subMessageCounter
        
        for tempStepMessage in messages {

            var stepMessage = Messaging_Step()

            stepMessage.timestamp = tempStepMessage.timestamp
            stepMessage.angle = tempStepMessage.angle

            if (subMessageCounter >= 0) {
                clientMessagesToCompile.append(stepMessage)
            } else {
                messagesToQueue.append(stepMessage)
            }

            subMessageNo += 1
        }
        
        return (subMessageNo, clientMessagesToCompile, messagesToQueue)
    }
    
    public func checkBluetoothTypeMessages(_ messages: [Messaging_Bluetooth],
                                       subMessageCounter: Int) -> (Int, [Messaging_Bluetooth], [Messaging_Bluetooth]) {
        var clientMessagesToCompile = [Messaging_Bluetooth]()
        var messagesToQueue = [Messaging_Bluetooth]()
        var subMessageNo = subMessageCounter
        
        for tempBluetoothMessage in messages {
            
            var bluetoothMessage = Messaging_Bluetooth()
            
            bluetoothMessage.identifier = tempBluetoothMessage.identifier
            bluetoothMessage.rssi = tempBluetoothMessage.rssi
            bluetoothMessage.tx = tempBluetoothMessage.tx
            bluetoothMessage.timestamp = tempBluetoothMessage.timestamp
            
            if (subMessageCounter >= 0) {
                clientMessagesToCompile.append(bluetoothMessage)
            } else {
                messagesToQueue.append(bluetoothMessage)
            }
            
            subMessageNo += 1
        }
        
        return (subMessageNo, clientMessagesToCompile, messagesToQueue)
    }
    
    public func checkiBeaconTypeMessages(_ messages: [Messaging_IBeacon],
                                           subMessageCounter: Int) -> (Int, [Messaging_IBeacon], [Messaging_IBeacon]) {
        var clientMessagesToCompile = [Messaging_IBeacon]()
        var messagesToQueue = [Messaging_IBeacon]()
        var subMessageNo = subMessageCounter
        
        for tempIbeaconMessage in messages {
            
            var ibeaconMessage = Messaging_IBeacon()
            
            ibeaconMessage.uuid = tempIbeaconMessage.uuid
            ibeaconMessage.major = tempIbeaconMessage.major
            ibeaconMessage.minor = tempIbeaconMessage.minor
            ibeaconMessage.rssi = tempIbeaconMessage.rssi
            ibeaconMessage.accuracy = tempIbeaconMessage.accuracy
            ibeaconMessage.timestamp = tempIbeaconMessage.timestamp
            ibeaconMessage.proximity = tempIbeaconMessage.proximity
            
            if (subMessageCounter >= 0) {
                clientMessagesToCompile.append(ibeaconMessage)
            } else {
                messagesToQueue.append(ibeaconMessage)
            }
            
            subMessageNo += 1
        }
        
        return (subMessageNo, clientMessagesToCompile, messagesToQueue)
    }
    
    public func checkEddystoneTypeMessages(_ messages: [Messaging_EddystoneBeacon],
                                         subMessageCounter: Int) -> (Int, [Messaging_EddystoneBeacon], [Messaging_EddystoneBeacon]) {
        var clientMessagesToCompile = [Messaging_EddystoneBeacon]()
        var messagesToQueue = [Messaging_EddystoneBeacon]()
        var subMessageNo = subMessageCounter
        
        for tempEddyStoneMessage in messages {
            
            var eddyStoneMessage = Messaging_EddystoneBeacon()
            
            eddyStoneMessage.eid = tempEddyStoneMessage.eid
            eddyStoneMessage.rssi = tempEddyStoneMessage.rssi
            eddyStoneMessage.timestamp = tempEddyStoneMessage.timestamp
            eddyStoneMessage.tx = tempEddyStoneMessage.tx
            
            if (subMessageCounter >= 0) {
                clientMessagesToCompile.append(eddyStoneMessage)
            } else {
                messagesToQueue.append(eddyStoneMessage)
            }
            
            subMessageNo += 1
        }
        
        return (subMessageNo, clientMessagesToCompile, messagesToQueue)
    }
    
    public func checkAliasesTypeMessages(_ messages: [Messaging_AliasMessage],
                                           subMessageCounter: Int) -> (Int, [Messaging_AliasMessage], [Messaging_AliasMessage]) {
        var clientMessagesToCompile = [Messaging_AliasMessage]()
        var messagesToQueue = [Messaging_AliasMessage]()
        var subMessageNo = subMessageCounter
        
        for tempAliasMessage in messages {
            
            var aliasMessage = Messaging_AliasMessage()
            
            aliasMessage.key = tempAliasMessage.key
            aliasMessage.value = tempAliasMessage.value
            
            if (subMessageCounter >= 0) {
                clientMessagesToCompile.append(aliasMessage)
            } else {
                messagesToQueue.append(aliasMessage)
            }
            
            subMessageNo += 1
        }
        
        return (subMessageNo, clientMessagesToCompile, messagesToQueue)
    }
    
    public func checkMessageIOSCapability(_ message: Messaging_IosCapability,
                                         subMessageCounter: Int) -> (Int, Messaging_IosCapability?, Messaging_IosCapability?) {
        let subMessageNo = subMessageCounter
        var capabilityMessage = Messaging_IosCapability()
        let tempCapabilityMessage = message
        
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
        
        if (subMessageNo >= 0) {
            return (subMessageNo + 1, capabilityMessage, nil)
        } else {
            return (subMessageNo + 1, nil, capabilityMessage)
        }
    }
    
    public func checkMarkerMessage(_ message: Messaging_ClientMessage,
                                   subMessageCounter: Int) -> (Int, Messaging_MarkerMessage?) {
        if (message.hasMarker){
            var markerMessage = Messaging_MarkerMessage()
            
            markerMessage.data = message.marker.data
            markerMessage.time = message.marker.time
            
            return (subMessageCounter + 1, markerMessage)
        } else {
            return (subMessageCounter, nil)
        }
    }
    
    public func checkNewBatteryLevelTypeMessage() -> (Messaging_Battery?) {
        var newBatteryMessage: Messaging_Battery? = nil
        if let isNewBatteryLevel = self.stateStore.state.batteryLevelState.isNewBatteryLevel {
            if isNewBatteryLevel {
                var batteryMessage = Messaging_Battery()
                
                if let batteryLevel = self.stateStore.state.batteryLevelState.batteryLevel {
                    batteryMessage.battery = batteryLevel
                    newBatteryMessage = batteryMessage
                    DispatchQueue.main.async {self.stateStore.dispatch(BatteryLevelReportedAction())}
                }
            }
        }
        return newBatteryMessage
    }
    
}
