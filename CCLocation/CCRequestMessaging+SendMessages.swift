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
            
            var connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
            
            if connectionState != .online {
                Log.verbose("Connection offline. Instant message inserted in db")
                
                self?.insertMessageInLocalDatabase(message: message)
            }
            
            connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
            
            var compiledClientMessage = Messaging_ClientMessage()
            var backToQueueMessages = Messaging_ClientMessage()
            
            var subMessageCounter:Int = 0
            var tempClientMessage:Messaging_ClientMessage?
            
            let tempMessage = message
            
            tempClientMessage = try? Messaging_ClientMessage(serializedData: tempMessage)
            
            if (tempClientMessage!.locationMessage.count > 0) {
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
                var markerMessage = Messaging_MarkerMessage()
                
                markerMessage.data = tempClientMessage!.marker.data
                markerMessage.time = tempClientMessage!.marker.time
                
                compiledClientMessage.marker = markerMessage
                
                subMessageCounter += 1
            }
            
            if let isNewBatteryLevel = self?.stateStore.state.batteryLevelState.isNewBatteryLevel {
                if isNewBatteryLevel {
                    var batteryMessage = Messaging_Battery()
                    
                    if let batteryLevel = self?.stateStore.state.batteryLevelState.batteryLevel {
                        batteryMessage.battery = batteryLevel
                        compiledClientMessage.battery = batteryMessage
                        DispatchQueue.main.async {self?.stateStore.dispatch(BatteryLevelReportedAction())}
                    }
                }
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
}
