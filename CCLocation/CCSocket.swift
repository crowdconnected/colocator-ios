//
//  CCSocket.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 15/08/2018.
//  Copyright © 2018 Crowd Connected. All rights reserved.
//

import Foundation
import CoreFoundation
import SocketRocket
import CoreLocation
import TrueTime

protocol CCSocketDelegate: AnyObject{
    func receivedTextMessage(message: NSDictionary)
    func ccSocketDidConnect()
    func ccSocketDidFailWithError(error: Error)
}

class CCSocket:NSObject {
    
    //private variables
    var webSocket: SRWebSocket?
    var running: Bool = false
    var deviceId: String?
    var ccServerURLString: String?
    var ccAPIKeyString: String?
    var ccWebsocketBaseURL: String?
    var ccLocationManager: CCLocationManager?
    var ccRequestMessaging: CCRequestMessaging?
    var ccInertial: CCInertial?
    var delay: Double = 0
    
    var maxCycleTimer: Timer?
    var firstReconnect: Bool = true
    var delegate: CCSocketDelegate?
    
    var pingTimer: Timer?
    var reconnectTimer: Timer?
    
    var startTime: Date?
    
    public static let sharedInstance: CCSocket = {
        let instance = CCSocket()
        return instance
    }()
    
    func start(urlString: String, apiKey: String,
               ccRequestMessaging: CCRequestMessaging, ccLocationManager: CCLocationManager, ccInertial: CCInertial){
        if !running {
            running = true
            startTime = Date()
            
            deviceId = UserDefaults.standard.string(forKey: CCSocketConstants.LAST_DEVICE_ID_KEY)
            
            ccServerURLString = urlString
            ccAPIKeyString = apiKey
            
            ccWebsocketBaseURL = CCSocketConstants.WS_PREFIX.appendingFormat("%@/%@", urlString, apiKey)
            
            self.ccLocationManager = ccLocationManager
            
            if let ccLocationManager = self.ccLocationManager {
                ccLocationManager.delegate = self
            }
            
            self.ccInertial = ccInertial
            
            if let ccInertial = self.ccInertial {
                ccInertial.delegate = self
            }
            
            self.ccRequestMessaging = ccRequestMessaging
            
            Log.debug("[Colocator] Started Colocator Framework")
            
            connect(timer: nil)
            
        } else {
            stop()
            start(urlString: urlString, apiKey: apiKey,
                  ccRequestMessaging: ccRequestMessaging, ccLocationManager: ccLocationManager, ccInertial: ccInertial)
        }
    }
    
    public func stop() {
        if running {
            running = false
            
            webSocket?.delegate = nil
            webSocket = nil
            
            ccLocationManager?.delegate = nil
            ccLocationManager = nil
            
            ccRequestMessaging = nil
            
            reconnectTimer?.invalidate()
            reconnectTimer = nil
            
            maxCycleTimer?.invalidate()
            maxCycleTimer = nil
            
            pingTimer?.invalidate()
            pingTimer = nil
            
            ccServerURLString = nil
            ccAPIKeyString = nil
            ccWebsocketBaseURL = nil
            startTime = nil
            
            Log.debug("[Colocator] Stopping Colocator")
        }
    }
    
    public func sendMarker(data: String) {
        if let ccRequestMessaging = self.ccRequestMessaging {
            ccRequestMessaging.processMarker(data: data)
        }
    }
    
    @objc public func connect(timer: Timer?) {
        var certRef: SecCertificate?
        var certDataRef: CFData?

        Log.debug("[Colocator] Establishing connection to Colocator servers ...")
        
        if timer == nil {
            Log.debug("first connect")
        } else {
            Log.debug("Timer fired")
        }
        
        if webSocket == nil {
            guard let ccWebsocketBaseURL = self.ccWebsocketBaseURL else {
                return
            }
            
            guard let socketURL = createWebsocketURL(url: ccWebsocketBaseURL, id: deviceId) else {
                Log.error("[Colocator] Construction of the Websocket connection request URL failed, will not attempt to connect to CoLocator backend")
                return
            }

            let platformConnectionRequest = NSMutableURLRequest(url: socketURL)

            if let cerPath = Bundle(for: type(of: self)).path(forResource: "certificate", ofType: "der") {
                do {
                    let certData = try Data(contentsOf: URL(fileURLWithPath: cerPath))
                    certDataRef = certData as CFData
                }
                catch {
                    Log.error("[Colocator] Could not create certificate data")
                }
            } else {
                Log.error("[Colocator] Could not find certificate file in Application Bundle, will not attempt to connect to CoLocator backend")
            }

            guard let certDataRefUnwrapped = certDataRef else {
                return
            }

            certRef = SecCertificateCreateWithData(nil, certDataRefUnwrapped)

            guard let certRefUnwrapped = certRef else {
                Log.error("[Colocator] Certificate is not a valid DER-encoded X.509 certificate")
                return
            }
            
            platformConnectionRequest.sr_SSLPinnedCertificates = [certRefUnwrapped]
            
            if platformConnectionRequest.url != nil {
                self.webSocket = SRWebSocket.init(urlRequest: platformConnectionRequest as URLRequest?)
                self.webSocket?.delegate = self
            }
            self.webSocket?.open()
        }
    }
    
    @objc public func stopCycler(timer: Timer) {
        if let ccLocationManager = self.ccLocationManager {
            ccLocationManager.stopAllLocationObservations()
        }
        self.maxCycleTimer = nil
    }
    
    public func delayReconnect() {
        if delay == 0 {
            delay = CCSocketConstants.MIN_DELAY
        }
        
        if pingTimer != nil {
            pingTimer!.invalidate()
        }

        Log.debug("Trying to reconnect in \(round((delay / 1000) * 100) / 100) s")
        
        reconnectTimer = Timer.scheduledTimer(timeInterval: delay/1000,
                                              target: self,
                                              selector: #selector(self.connect(timer:)),
                                              userInfo: nil,
                                              repeats: false)
        
        if delay * 1.2 < CCSocketConstants.MAX_DELAY {
            delay = delay * 1.2
        } else {
            delay = CCSocketConstants.MAX_DELAY
        }
        
        if maxCycleTimer == nil && firstReconnect {
            maxCycleTimer = Timer.scheduledTimer(timeInterval: CCSocketConstants.MAX_CYCLE_DELAY / 1000,
                                                 target: self,
                                                 selector: #selector(self.stopCycler(timer:)),
                                                 userInfo: nil,
                                                 repeats: false)
        }
        firstReconnect = false
    }
    
    public func setAliases(aliases: Dictionary<String, String>) {
        UserDefaults.standard.set(aliases, forKey: CCSocketConstants.ALIAS_KEY)
        if let ccRequestMessaging = self.ccRequestMessaging {
            ccRequestMessaging.processAliases(aliases: aliases)
        }
    }
    
    public func setDeviceId(deviceId: String) {
        self.deviceId = deviceId
        UserDefaults.standard.set(self.deviceId!, forKey: CCSocketConstants.LAST_DEVICE_ID_KEY)
    }
        
    public func getStartTimeSwiftBridge() -> Date {
        return self.startTime!
    }
        
    public func sendWebSocketMessage(data: Data) {
        if webSocket != nil {
            webSocket?.send(data)
        }
    }
    
    public func createWebsocketURL(url: String, id: String?) -> URL? {
        var requestURL: URL?
        var queryString: String?
            
        queryString = id != nil ? String(format: "?id=%@&", id!) : "?"
        
        queryString! += self.deviceDescription()
        queryString! += self.networkType()
        queryString! += self.libraryVersion()
        
        if queryString!.isEmpty {
            queryString = "?error=inQueryStringConstruction"
        } else {
            queryString = queryString!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        }

        guard let queryStringUnwrapped = queryString else {
            return nil
        }
        
        Log.debug("Query string is \(queryString ?? "NOT AVAILABLE")")
        
        requestURL = URL(string: url)
        requestURL = URL(string: queryStringUnwrapped, relativeTo: requestURL)
        
        return requestURL
    }
    
    func deviceDescription() -> String {
        let deviceModel = self.platformString()
        let deviceOs = "iOS"
        let deviceVersion = UIDevice.current.systemVersion
        
        return String(format: "model=%@&os=%@&version=%@", deviceModel, deviceOs, deviceVersion)
    }
    
    func networkType() -> String {
        var networkType: String = ""
        
        if ReachabilityManager.shared.isReachableViaWiFi() {
            networkType = "&networkType=WIFI"
        }
        if ReachabilityManager.shared.isReachableViaWan() {
            networkType = "&networkType=MOBILE"
        }
        
        return networkType
    }
    
    func libraryVersion() -> String {
        let libraryVersion = CCSocketConstants.LIBRARY_VERSION_TO_REPORT
        return String(format: "&libVersion=%@" , libraryVersion)
    }
    
    func platform() -> NSString {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0,  count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine) as NSString
    }
    
    func platformString() -> String {
        let platform = self.platform()
        guard let devicePlatform = DevicePlatform(rawValue: String(platform)) else {
            return platform as String
        }
        
        return devicePlatform.title
    }
    
    deinit {
        Log.debug("CCRequestMessaging DEINIT")
        
        if #available(iOS 10.0, *) {
            Log.debug("[CC] CCRequestMessaging DEINIT")
        } else {
            // Fallback on earlier versions
        }
    }
}

// MARK: CCLocationManagerDelegate
extension CCSocket: CCLocationManagerDelegate {
    public func receivedEddystoneBeaconInfo(eid: NSString, tx: Int, rssi: Int, timestamp: TimeInterval) {
        let tempString = String(eid).hexa2Bytes
        ccRequestMessaging?.processEddystoneEvent(eid: NSData(bytes: tempString, length: tempString.count) as Data,
                                                  tx: tx,
                                                  rssi: rssi,
                                                  timestamp: timestamp)
    }
    
    public func receivedGEOLocation(location: CLLocation) {
        ccRequestMessaging?.processLocationEvent(location: location)
    }
    
    public func receivediBeaconInfo(proximityUUID: UUID,
                                    major: Int,
                                    minor: Int,
                                    proximity: Int,
                                    accuracy: Double,
                                    rssi: Int,
                                    timestamp: TimeInterval) {
        ccRequestMessaging?.processIBeaconEvent(uuid: proximityUUID,
                                                major: major,
                                                minor: minor,
                                                rssi: rssi,
                                                accuracy: accuracy,
                                                proximity: proximity,
                                                timestamp: timestamp)
    }
}

// MARK: CCInertialDelegate
extension CCSocket: CCInertialDelegate {
    func receivedStep(date: Date, angle: Double) {
        ccRequestMessaging?.processStep(date: date, angle: angle)
    }
}

// MARK: SRWebSocketDelegate
extension CCSocket: SRWebSocketDelegate {
    public func webSocketDidOpen(_ webSocket: SRWebSocket!) {
        Log.debug("[Colocator] ... connection to back-end established")
        
        guard let ccRequestMessagingUnwrapped = ccRequestMessaging else {
            return
        }
        
        ccRequestMessagingUnwrapped.webSocketDidOpen()
        
        delay = CCSocketConstants.MIN_DELAY
                
        if let timer = maxCycleTimer {
            timer.invalidate()
        }
        
        maxCycleTimer = nil
        firstReconnect = true
        
        if let delegate = self.delegate {
            delegate.ccSocketDidConnect()
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!) {
        Log.error("[Colocator] :( Connection failed With Error " + error.localizedDescription)
        
        guard let ccRequestMessaging = self.ccRequestMessaging else {
            return
        }
        
        self.webSocket?.delegate = nil
        self.webSocket = nil
        
        ccRequestMessaging.webSocketDidClose()
        
        if let delegate = self.delegate {
            delegate.ccSocketDidFailWithError(error: error)
        }
        
        delayReconnect()
    }
    
    public func webSocket(_ webSocket: SRWebSocket!, didReceiveMessage message: Any!) {
        guard let ccRequestMessaging = self.ccRequestMessaging else {
            return
        }
        
        var message_data: Data? = nil
        
        if message is String || message is NSString {
            
            message_data = (message as! String).data(using: .utf8)!
            
        } else if message is Data || message is NSData {
            
            message_data = message as? Data
        }
        
        do {
            try ccRequestMessaging.processServerMessage(data: message_data!)
        } catch {
            Log.error("[Colocator] :( processing server message failed");
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket!, didCloseWithCode code: Int, reason: String!, wasClean: Bool) {
        self.webSocket?.delegate = nil
        self.webSocket = nil
        
        delayReconnect()
    }
}

extension StringProtocol {
    var hexa2Bytes: [UInt8] {
        let hexa = Array(self)
        return stride(from: 0, to: count, by: 2).compactMap {
            UInt8(String(hexa[$0..<$0.advanced(by: 2)]), radix: 16)
        }
    }
}
