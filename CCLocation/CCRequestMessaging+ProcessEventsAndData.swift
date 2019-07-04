//
//  CCRequestMessaging+ProcessEventsAndData.swift
//  CCLocation
//
//  Created by Mobile Developer on 04/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import Foundation
import CoreLocation
import ReSwift
import CoreBluetooth

// Extension Process Events and Data

extension CCRequestMessaging {
    
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
    
    public func processLocationEvent(location: CLLocation) {
        
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
    
}

