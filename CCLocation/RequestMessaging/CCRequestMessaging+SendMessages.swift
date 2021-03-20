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
    
    // If the databse in empty, just send the last reported message to the server
    // Otherwise send all the messages in the database in order
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
    
    // A client message can contain maximum 100 reports (ex: step, beacon signal, location, capability)
    // If there are more reports in the database, multiple messages will be sent
    private func sendAllMessagesFromDatabase() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                return
            }

            let maxMessagesToReturn = 100
            let messageNumber = self.getMessageCount()
            var connectionState = self.getStateConnectionState()

            Log.verbose ("\(messageNumber) Queued messages are available")
            
            while self.getMessageCount() > 0 && connectionState == .online {
                connectionState = self.getStateConnectionState()
                
                var compiledClientMessage = Messaging_ClientMessage()
                var backToQueueMessages = Messaging_ClientMessage()
                
                var tempMessageData: [Data]?
                var subMessageCounter: Int = 0
                
                while self.getMessageCount() > 0 && subMessageCounter < maxMessagesToReturn {
                    tempMessageData = self.popMessagesFromLocalDatabase(maxMessagesToReturn: maxMessagesToReturn)
                    
                    if let unwrappedTempMessageData = tempMessageData {
                        for tempMessage in unwrappedTempMessageData {
                            let (newSubMessageCounter,
                                 newCompiledClientMessage,
                                 newBackToQueueMessages) = self.handleMessageType(message: tempMessage,
                                                                                   subMessageInitialNumber: subMessageCounter,
                                                                                   compiledMessage: compiledClientMessage,
                                                                                   queueMessage: backToQueueMessages)
                            subMessageCounter = newSubMessageCounter
                            compiledClientMessage = newCompiledClientMessage
                            backToQueueMessages = newBackToQueueMessages
                        }
                    }
                }
                
                self.handleMessageBackToQueue(backToQueueMessages)
                
                if let data = try? compiledClientMessage.serializedData(), data.count > 0 {
                    self.setupSentTime(forMessage: &compiledClientMessage)
                    self.sendMessageThroughSocket(compiledClientMessage)
                }
            }
        }
    }
    
    // Sending a single message, ignores the databse and creates a client message with the exact data received as parameter
    func sendSingleMessage(_ message: Data) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                return
            }

            var (_, compiledClientMessage, backToQueueMessage) = self.handleMessageType(message: message)
            self.handleMessageBackToQueue(backToQueueMessage)
        
            if let data = try? compiledClientMessage.serializedData(), data.count > 0 {
                self.setupSentTime(forMessage: &compiledClientMessage)
                self.sendMessageThroughSocket(compiledClientMessage)
            }
        }
    }
    
    private func handleMessageBackToQueue(_ message: Messaging_ClientMessage) {
        if let backToQueueData = try? message.serializedData() {
            if backToQueueData.count > 0 {
                insertMessageInLocalDatabase(message: backToQueueData)
                Log.debug("Had to split a client message into two, pushing \(backToQueueData.count) unsent messages back to the Queue")
            }
        } else {
            Log.error("[Colocator] Couldn't serialize back to queue data")
        }
    }
    
    // Every client message requires the true time added as timestamp
    // The local time on the device cannot be used since the data must be correct and uniform across all the devices
    private func setupSentTime(forMessage message: inout Messaging_ClientMessage) {
        guard let stateStore = stateStore else {
            Log.error("State store is nil when attempting to insert a beacon in the database")
            return
        }
        let isRebootTimeSame = timeHandling.isRebootTimeSame(stateStore: stateStore, ccSocket: ccSocket)
        let currentTimePeriod = TimeHandling.getCurrentTimePeriodSince1970(stateStore: stateStore)
        
        if isRebootTimeSame && currentTimePeriod != nil {
            message.sentTime = UInt64(currentTimePeriod! * 1000)
            
            if message.sentTime == 0 {
                Log.error("[Colocator] Client message timestamp 0! \(message)")
            }
        }
    }
    
    private func sendMessageThroughSocket(_ message: Messaging_ClientMessage) {
        if let messageData = try? message.serializedData() {
            Log.verbose("Sending \(messageData.count) bytes of compiled instant message data")
            
            ccSocket?.sendWebSocketMessage(data: messageData)
            
            Log.info("[Colocator]  Sent message to server")
        }
    }
}
