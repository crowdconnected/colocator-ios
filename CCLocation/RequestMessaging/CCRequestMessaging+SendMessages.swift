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
        if let newMessage = firstMessage {
            if self.getMessageCount() > 0 {
                insertMessageInLocalDatabase(message: newMessage)
                sendAllMessagesFromDatabase()
            } else {
                sendSingleMessage(firstMessage!)
            }
        } else {
            sendAllMessagesFromDatabase()
        }
    }
    
    private func sendAllMessagesFromDatabase() {
        var workItem: DispatchWorkItem!
        
        workItem = DispatchWorkItem { [weak self] in
            
            if !workItem.isCancelled {
                let maxMessagesToReturn = 100
                let connectionState = self?.stateStore.state.ccRequestMessagingState.webSocketState?.connectionState
                
                let messageNumber = self?.getMessageCount() ?? -1
                Log.verbose ("\(messageNumber) Queued messages are available")
                
                while self?.getMessageCount() ?? -1 > 0 && connectionState == .online {
                    if workItem.isCancelled { break }
                    
                    var compiledClientMessage = Messaging_ClientMessage()
                    var backToQueueMessages = Messaging_ClientMessage()
                    
                    var tempMessageData: [Data]?
                    var subMessageCounter: Int = 0
                    
                    while self?.getMessageCount() ?? -1 > 0
                        && subMessageCounter < maxMessagesToReturn {
                        
                        if workItem.isCancelled { break }
                        
                        tempMessageData = self?.popMessagesFromLocalDatabase(maxMessagesToReturn: maxMessagesToReturn)
                        
                        if let unwrappedTempMessageData = tempMessageData {
                            for tempMessage in unwrappedTempMessageData {
                                if workItem.isCancelled { break }
                                
                                let (newSubMessageCounter,
                                     newCompiledClientMessage,
                                     newBackToQueueMessages) = self?.handleMessageType(message: tempMessage,
                                                                                       subMessageInitialNumber: subMessageCounter,
                                                                                       compiledMessage: compiledClientMessage,
                                                                                       queueMessage: backToQueueMessages)
                                                                ?? (subMessageCounter,
                                                                    Messaging_ClientMessage(),
                                                                    Messaging_ClientMessage())
                                
                                subMessageCounter = newSubMessageCounter
                                compiledClientMessage = newCompiledClientMessage
                                backToQueueMessages = newBackToQueueMessages
                            }
                        }
                    }
                    
                    if workItem.isCancelled { break }
                    
                    self?.logMessageContent(compiledClientMessage, subMessageCounter: subMessageCounter)
                    
                    if workItem.isCancelled { break }
                    
                    self?.handleMessageBackToQueue(backToQueueMessages, subMessageCounter: subMessageCounter)
                    
                    if workItem.isCancelled { return }
                    
                    if let data = try? compiledClientMessage.serializedData(), data.count > 0 {
                        self?.setupSentTime(forMessage: &compiledClientMessage)
                        self?.sendMessageThroughSocket(compiledClientMessage)
                    }
                }
                
                if workItem.isCancelled { return }
                
                self?.removeWorkItem(workItem)
                workItem = nil
            }
        }
        
        workItems.append(workItem)
        
        DispatchQueue.global(qos: .background).async(execute: workItem)
    }
    
    private func removeWorkItem(_ item: DispatchWorkItem) {
        if let index = self.workItems.index(where: {$0 === item}) {
            // Awkward, it happened to throw index out of range error
            // Just checking index before trying to remove
            if index < self.workItems.count {
                self.workItems.remove(at: index)
            }
        }
    }
    
    private func logMessageContent(_ message: Messaging_ClientMessage, subMessageCounter: Int) {
        Log.verbose("Compiled \(subMessageCounter) message(s)")
        
        if message.locationMessage.count > 0 {
            let geoMsg = message.locationMessage[0]
            let geoData = try? geoMsg.serializedData()
            Log.verbose("Compiled geoMsg: \(geoData?.count ?? -1) and byte array: \(geoData?.hexEncodedString() ?? "NOT AVAILABLE")")
        }
        
        if message.bluetoothMessage.count > 0 {
            let blMsg = message.bluetoothMessage[0]
            let blData = try? blMsg.serializedData()
            Log.verbose("Compiled bluetooth message: \(blData?.count ?? -1) and byte array: \(blData?.hexEncodedString() ?? "NOT AVAILABLE"))")
        }
        
        for beacon in message.ibeaconMessage {
            Log.verbose("Sending beacons \(message.ibeaconMessage.count) with \(beacon)")
        }
        
        if message.alias.count > 0 {
            let alMsg = message.alias[0]
            let alData = try? alMsg.serializedData()
            Log.verbose("Compiled alias message: \(alData?.count ?? -1)  and byte array: \(alData?.hexEncodedString() ?? "NOT AVAILABLE"))")
        }
    }
    
    private func sendSingleMessage(_ message: Data) {
        var workItem: DispatchWorkItem!
        
        workItem = DispatchWorkItem { [weak self] in
            if workItem.isCancelled { return }
            
            var (subMessageCounter,
                 compiledClientMessage,
                 backToQueueMessage) = self?.handleMessageType(message: message) ?? (0,
                                                                                     Messaging_ClientMessage(),
                                                                                     Messaging_ClientMessage())
            
            self?.handleMessageBackToQueue(backToQueueMessage, subMessageCounter: subMessageCounter)
            
            if workItem.isCancelled { return }
            
            if let data = try? compiledClientMessage.serializedData(), data.count > 0 {
                self?.setupSentTime(forMessage: &compiledClientMessage)
                self?.sendMessageThroughSocket(compiledClientMessage)
            }
        }
        
        DispatchQueue.global(qos: .background).async(execute: workItem)
    }
    
    private func handleMessageBackToQueue(_ message: Messaging_ClientMessage, subMessageCounter: Int) {
        if let backToQueueData = try? message.serializedData() {
            Log.debug("Had to split a client message into two, pushing \(subMessageCounter) unsent messages back to the Queue")
            
            if backToQueueData.count > 0 {
                insertMessageInLocalDatabase(message: backToQueueData)
            }
        } else {
            Log.error("Couldn't serialize back to queue data")
        }
    }
    
    private func setupSentTime(forMessage message: inout Messaging_ClientMessage) {
        let isRebootTimeSame = self.timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket)
        let currentTimePeriod = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore)
        
        if isRebootTimeSame && currentTimePeriod != nil {
            message.sentTime = UInt64(currentTimePeriod! * 1000)
            
            if message.sentTime == 0 {
                Log.error("Client message timestamp 0")
                Log.error(message)
            }
        }
    }
    
    private func sendMessageThroughSocket(_ message: Messaging_ClientMessage) {
        if let messageData = try? message.serializedData() {
            Log.verbose("Sending \(messageData.count) bytes of compiled instant message data")
            
            ccSocket?.sendWebSocketMessage(data: messageData)
            
            Log.info("Message sent to server")
        }
    }
}
