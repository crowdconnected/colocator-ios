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
        
        workItem = DispatchWorkItem { [weak self] in
            
            if !workItem.isCancelled {
                
                if self == nil {
                    //This should not happen
                    Log.error("Self object is nil inside sending message method. Message won't be delivered or queued")
                    return
                }
                
                let maxMessagesToReturn = 100
                
                var connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
                
                while (self?.getMessageCount() ?? -1 > 0 && connectionState == .online) {
                    
                    if workItem.isCancelled { break }
                    
                    connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
                    
                    var compiledClientMessage = Messaging_ClientMessage()
                    var backToQueueMessages = Messaging_ClientMessage()
                    
                    var tempMessageData:[Data]?
                    var subMessageCounter:Int = 0
                    
                    let messageNumber = self?.getMessageCount() ?? -1
                    
                    if (messageNumber == 0) {
                        Log.verbose ("No queued messages available to send")
                    }
                    
                    Log.verbose ("\(messageNumber) Queued messages are available")
                    
                    while (self?.getMessageCount() ?? -1 > 0 && subMessageCounter < maxMessagesToReturn) {
                        
                        if workItem.isCancelled { break }
                        
                        tempMessageData = self?.popMessagesFromLocalDatabase(maxMessagesToReturn: maxMessagesToReturn)
                        
                        if let unwrappedTempMessageData = tempMessageData {
                            for tempMessage in unwrappedTempMessageData {
                                
                                if workItem.isCancelled { break }
                                
                                let (newSubMessageCounter, newCompiledClientMessage, newBackToQueueMessages) = self?.handleMessageType(message: tempMessage,
                                                                                                                                       subMessageInitialNumber: subMessageCounter,
                                                                                                                                       compiledMessage: compiledClientMessage,
                                                                                                                                       queueMessage: backToQueueMessages) ?? (subMessageCounter, Messaging_ClientMessage(),Messaging_ClientMessage())
                                subMessageCounter = newSubMessageCounter
                                compiledClientMessage = newCompiledClientMessage
                                backToQueueMessages = newBackToQueueMessages
                            }
                        }
                    }
                    
                    Log.verbose("Compiled \(subMessageCounter) message(s)")
                    
                    if (compiledClientMessage.locationMessage.count > 0) {
                        let geoMsg = compiledClientMessage.locationMessage[0]
                        let geoData = try? geoMsg.serializedData()
                        Log.verbose("Compiled geoMsg: \(geoData?.count ?? -1) and byte array: \(geoData?.hexEncodedString() ?? "NOT AVAILABLE")")
                    }
                    if (compiledClientMessage.bluetoothMessage.count > 0) {
                        let blMsg = compiledClientMessage.bluetoothMessage[0]
                        let blData = try? blMsg.serializedData()
                        Log.verbose("Compiled bluetooth message: \(blData?.count ?? -1) and byte array: \(blData?.hexEncodedString() ?? "NOT AVAILABLE"))")
                    }
                    for beacon in compiledClientMessage.ibeaconMessage {
                        Log.verbose("Sending beacons \(compiledClientMessage.ibeaconMessage.count) with \(beacon)")
                    }
                    if (compiledClientMessage.alias.count > 0) {
                        let alMsg = compiledClientMessage.alias[0]
                        let alData = try? alMsg.serializedData()
                        Log.verbose("Compiled alias message: \(alData?.count ?? -1)  and byte array: \(alData?.hexEncodedString() ?? "NOT AVAILABLE"))")
                    }
                    
                    if workItem.isCancelled { break }
                    
                    if let backToQueueData = try? backToQueueMessages.serializedData() {
                        Log.debug("Had to split a client message into two, pushing \(subMessageCounter) unsent messages back to the Queue")
                        if backToQueueData.count > 0 {
                            //    ccRequest?.messageQueuePushSwiftBridge(backToQueueData)
                            
                            self?.insertMessageInLocalDatabase(message: backToQueueData)
                        }
                    } else {
                        Log.error("Couldn't serialize back to queue data")
                    }
                    
                    if let data = try? compiledClientMessage.serializedData(), data.count > 0 {
                        if let stateStore = self?.stateStore,
                            let ccSocket = self?.ccSocket {
                            
                            if let isRebootTimeSame = self?.timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket) {
                                if isRebootTimeSame {
                                    if let currentTimePeriod = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore) {
                                        compiledClientMessage.sentTime = UInt64(currentTimePeriod * 1000)
                                        Log.verbose("Added sent time to the client message")
                                    }
                                }
                            }
                            
                            if let dataIncludingSentTime = try? compiledClientMessage.serializedData(){
                                Log.verbose("Sending \(dataIncludingSentTime.count) bytes of compiled client message data")
                                self?.ccSocket?.sendWebSocketMessage(data: dataIncludingSentTime)
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
            
            var (subMessageCounter, compiledClientMessage, backToQueueMessage) = self?.handleMessageType(message: message) ?? (0, Messaging_ClientMessage(),Messaging_ClientMessage())
            
            if let backToQueueData = try? backToQueueMessage.serializedData() {
                Log.debug("Had to split a client message into two, pushing \(subMessageCounter) unsent messages back to the Queue")
                if backToQueueData.count > 0 {
                    //    ccRequest?.messageQueuePushSwiftBridge(backToQueueData)
                    
                    self?.insertMessageInLocalDatabase(message: backToQueueData)
                }
            } else {
                Log.error("Couldn't serialize back to queue data")
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
                            
                            Log.info("Instant message sent to server")
                        }
                    }
                }
            }
        }
        
        DispatchQueue.global(qos: .background).async(execute: workItem)
    }
}
