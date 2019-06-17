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
    
    public static let sharedInstance : CCSocket = {
        let instance = CCSocket()
        return instance
    }()
    
    func start(urlString: String, apiKey: String, ccRequestMessaging: CCRequestMessaging, ccLocationManager: CCLocationManager, ccInertial: CCInertial){
        
        if (!running){
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
            start(urlString: urlString, apiKey: apiKey, ccRequestMessaging: ccRequestMessaging, ccLocationManager: ccLocationManager, ccInertial: ccInertial)
        }
    }
    
    public func stop() {
        if (running) {
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
        
        if (timer == nil) {
            Log.debug("first connect")
        } else {
            Log.debug("Timer fired")
        }
        
        if (webSocket == nil) {
            
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
            
            if (platformConnectionRequest.url == nil){
            } else {
                self.webSocket = SRWebSocket.init(urlRequest: platformConnectionRequest as URLRequest?)
                self.webSocket?.delegate = self
            }
            self.webSocket?.open()
        }
    }
    
    @objc public func stopCycler(timer: Timer){
        if let ccLocationManager = self.ccLocationManager{
            ccLocationManager.stopAllLocationObservations()
        }
        self.maxCycleTimer = nil
    }
    
    public func delayReconnect(){
        if (delay == 0){
            delay = CCSocketConstants.MIN_DELAY
        }
        
        if pingTimer != nil{
            pingTimer!.invalidate()
        }

        Log.debug("Trying to reconnect in \(round((delay / 1000) * 100) / 100) s")
        
        reconnectTimer = Timer.scheduledTimer(timeInterval: delay/1000, target: self, selector: #selector(self.connect(timer:)), userInfo: nil, repeats: false)
        
        if (delay * 1.2 < CCSocketConstants.MAX_DELAY){
            delay = delay * 1.2
        } else {
            delay = CCSocketConstants.MAX_DELAY
        }
        
        if (maxCycleTimer == nil && firstReconnect) {
            maxCycleTimer = Timer.scheduledTimer(timeInterval: CCSocketConstants.MAX_CYCLE_DELAY / 1000, target: self, selector: #selector(self.stopCycler(timer:)), userInfo: nil, repeats: false)
        }
        
        firstReconnect = false
    }
    
    public func setAliases(aliases: Dictionary<String, String>){
            UserDefaults.standard.set(aliases, forKey: CCSocketConstants.ALIAS_KEY)
            if let ccRequestMessaging = self.ccRequestMessaging {
                ccRequestMessaging.processAliases(aliases: aliases)
        }
    }
    
    public func setDeviceId(deviceId: String){
        self.deviceId = deviceId
        UserDefaults.standard.set(self.deviceId!, forKey: CCSocketConstants.LAST_DEVICE_ID_KEY)
    }
        
    public func getStartTimeSwiftBridge() -> Date {
        return self.startTime!
    }
        
    public func sendWebSocketMessage(data: Data){
        if webSocket != nil {
            webSocket?.send(data)
        }
    }
    
    public func createWebsocketURL(url: String, id: String?) -> URL? {
        var requestURL: URL?
        var queryString: String?
            
        queryString = id != nil ? String(format: "?id=%@&", id!) : "?"
        
        queryString! += self.deviceDescription()
        queryString! += self.networkType();
        queryString! += self.libraryVersion();
        
        if (queryString!.isEmpty) {
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
    
    func deviceDescription() -> String{
        let deviceModel = self.platformString()
        let deviceOs = "iOS"
        let deviceVersion = UIDevice.current.systemVersion
        
        return String(format: "model=%@&os=%@&version=%@", deviceModel, deviceOs, deviceVersion)
    }
    
    func networkType() -> String{
        var networkType: String = ""
        
        if (ReachabilityManager.shared.isReachableViaWiFi())    {networkType = "&networkType=WIFI"}
        if (ReachabilityManager.shared.isReachableViaWan())     {networkType = "&networkType=MOBILE"}
        
        return networkType
    }
    
    func libraryVersion() -> String{
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
    
    func platformString() -> String{
        let platform = self.platform()
        
        /* iPhone */
        if (platform.isEqual(to:"iPhone1,1"))    {return "iPhone_1G"}
        if (platform.isEqual(to:"iPhone1,2"))    {return "iPhone_3G"}
        if (platform.isEqual(to:"iPhone2,1"))    {return "iPhone_3GS"}
        if (platform.isEqual(to:"iPhone3,1"))    {return "iPhone_4"}
        if (platform.isEqual(to:"iPhone3,3"))    {return "Verizon_iPhone_4"}
        if (platform.isEqual(to:"iPhone4,1"))    {return "iPhone_4S"}
        if (platform.isEqual(to:"iPhone5,1"))    {return "iPhone_5-GSM"}
        if (platform.isEqual(to:"iPhone5,2"))    {return "iPhone_5-GSM+CDMA"}
        if (platform.isEqual(to:"iPhone5,3"))    {return "iPhone_5c-GSM"}
        if (platform.isEqual(to:"iPhone5,4"))    {return "iPhone_5c-GSM_CDMA"}
        if (platform.isEqual(to:"iPhone6,1"))    {return "iPhone_5s-GSM"}
        if (platform.isEqual(to:"iPhone6,2"))    {return "iPhone_5s-GSM_CDMA"}
        
        if (platform.isEqual(to:"iPhone7,1"))    {return "iPhone_6_Plus"}
        if (platform.isEqual(to:"iPhone7,2"))    {return "iPhone_6"}
        if (platform.isEqual(to:"iPhone8,1"))    {return "iPhone_6s"}
        if (platform.isEqual(to:"iPhone8,2"))    {return "iPhone_6s_Plus"}
        if (platform.isEqual(to:"iPhone8,4"))    {return "iPhone_SE"}
        
        if (platform.isEqual(to:"iPhone9,1"))    {return "iPhone_7_(Global)"}
        if (platform.isEqual(to:"iPhone9,3"))    {return "iPhone_7_(GSM)"}
        if (platform.isEqual(to:"iPhone9,2"))    {return "iPhone_7_Plus_(Global)"}
        if (platform.isEqual(to:"iPhone9,4"))    {return "iPhone_7_Plus_(GSM)"}
        
        if (platform.isEqual(to:"iPhone10,1"))    {return "iPhone_8"}
        if (platform.isEqual(to:"iPhone10,4"))    {return "iPhone_8"}
        if (platform.isEqual(to:"iPhone10,2"))    {return "iPhone_8_Plus"}
        if (platform.isEqual(to:"iPhone10,5"))    {return "iPhone_8_Plus"}
        
        if (platform.isEqual(to:"iPhone10,3"))   {return "iPhone_X"}
        if (platform.isEqual(to:"iPhone10,6"))   {return "iPhone_X"}
        
        /* iPod */
        
        if (platform.isEqual(to:"iPod1,1"))      {return "iPod_Touch_1G"}
        if (platform.isEqual(to:"iPod2,1"))      {return "iPod_Touch_2G"}
        if (platform.isEqual(to:"iPod3,1"))      {return "iPod_Touch_3G"}
        if (platform.isEqual(to:"iPod4,1"))      {return "iPod_Touch_4G"}
        if (platform.isEqual(to:"iPod5,1"))      {return "iPod_Touch_5G"}
        if (platform.isEqual(to:"iPod7,1"))      {return "iPod_Touch_6G"}
       
        /* iPad */
        
        if (platform.isEqual(to:"iPad1,1"))      {return "iPad"}
        if (platform.isEqual(to:"iPad2,1"))      {return "iPad_2-WiFi"}
        if (platform.isEqual(to:"iPad2,2"))      {return "iPad_2-GSM"}
        if (platform.isEqual(to:"iPad2,3"))      {return "iPad_2-CDMA"}
        if (platform.isEqual(to:"iPad2,4"))      {return "iPad_2-WiFi"}
        if (platform.isEqual(to:"iPad2,5"))      {return "iPad_Mini-WiFi"}
        if (platform.isEqual(to:"iPad2,6"))      {return "iPad_Mini-GSM"}
        if (platform.isEqual(to:"iPad2,7"))      {return "iPad_Mini-GSM_CDMA)"}
        if (platform.isEqual(to:"iPad3,1"))      {return "iPad_3-WiFi"}
        if (platform.isEqual(to:"iPad3,2"))      {return "iPad_3-GSM_CDMA"}
        if (platform.isEqual(to:"iPad3,3"))      {return "iPad_3-GSM"}
        if (platform.isEqual(to:"iPad3,4"))      {return "iPad_4-WiFi"}
        if (platform.isEqual(to:"iPad3,5"))      {return "iPad_4-GSM"}
        if (platform.isEqual(to:"iPad3,6"))      {return "iPad_4-GSM_CDMA"}
        if (platform.isEqual(to:"iPad4,1"))      {return "iPad_Air-WiFi"}
        if (platform.isEqual(to:"iPad4,2"))      {return "iPad_Air-Cellular"}
        if (platform.isEqual(to:"iPad4,4"))      {return "iPad_mini_2G-WiFi"}
        if (platform.isEqual(to:"iPad4,5"))      {return "iPad_mini_2G-Cellular"}
        
        if (platform.isEqual(to:"iPad4,6"))      {return "iPad_Mini_2"}
        if (platform.isEqual(to:"iPad4,7"))      {return "iPad_Mini_3"}
        if (platform.isEqual(to:"iPad4,8"))      {return "iPad_Mini_3"}
        if (platform.isEqual(to:"iPad4,9"))      {return "iPad_Mini_3"}
        if (platform.isEqual(to:"iPad5,1"))      {return "iPad_Mini_4_(WiFi)"}
        if (platform.isEqual(to:"iPad5,2"))      {return "iPad_Mini_4_(LTE)"}
        if (platform.isEqual(to:"iPad5,3"))      {return "iPad_Air_2"}
        if (platform.isEqual(to:"iPad5,4"))      {return "iPad_Air_2"}
        if (platform.isEqual(to:"iPad6,3"))      {return "iPad_Pro_9.7"}
        if (platform.isEqual(to:"iPad6,4"))      {return "iPad_Pro_9.7"}
        if (platform.isEqual(to:"iPad6,7"))      {return "iPad_Pro_12.9"}
        if (platform.isEqual(to:"iPad6,8"))      {return "iPad_Pro_12.9"}
    
        if (platform.isEqual(to:"iPad6,11"))     {return "iPad_5G"}
        if (platform.isEqual(to:"iPad6,12"))     {return "iPad_5G"}
        if (platform.isEqual(to:"iPad7,1"))      {return "iPad_Pro_12.9_2G"}
        if (platform.isEqual(to:"iPad7,2"))      {return "iPad_Pro_12.9_2G"}
        if (platform.isEqual(to:"iPad7,3"))      {return "iPad_Pro_10.5"}
        if (platform.isEqual(to:"iPad7,4"))      {return "iPad_Pro_10.5"}
        
        if (platform.isEqual(to:"i386"))         {return "Simulator"}
        if (platform.isEqual(to:"x86_64"))       {return "Simulator"}
        return platform as String;
    }
    
    deinit {
        //        DDLogVerbose("CCRequestMessaging DEINIT")
        //        if #available(iOS 10.0, *) {
        //            os_log("[CC] CCRequestMessaging DEINIT")
        //        } else {
        //            // Fallback on earlier versions
        //        }
    }
}

// MARK: CCLocationManagerDelegate
extension CCSocket: CCLocationManagerDelegate {
    public func receivedEddystoneBeaconInfo(eid: NSString, tx: Int, rssi: Int, timestamp: TimeInterval) {
    
        let tempString = String(eid).hexa2Bytes
        
        ccRequestMessaging?.processEddystoneEvent(eid: NSData(bytes: tempString, length: tempString.count) as Data, tx: tx, rssi: rssi, timestamp: timestamp)
    }
    
    public func receivedGEOLocation(location: CLLocation) {
        ccRequestMessaging?.processLocationEvent(location: location)
    }
    
    public func receivediBeaconInfo(proximityUUID: UUID, major: Int, minor: Int, proximity: Int, accuracy: Double, rssi: Int, timestamp: TimeInterval) {
        ccRequestMessaging?.processIBeaconEvent(uuid: proximityUUID, major: major, minor: minor, rssi: rssi, accuracy: accuracy, proximity: proximity, timestamp: timestamp)
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
        Log.error("[Colocator] :( Connection failed With Error " + error.localizedDescription);
        
        guard let ccRequestMessaging = self.ccRequestMessaging else{
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
        
        if (message is String || message is NSString){
            message_data = (message as! String).data(using: .utf8)!
        }else if (message is Data || message is NSData){
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
        return stride(from: 0, to: count, by: 2).compactMap { UInt8(String(hexa[$0..<$0.advanced(by: 2)]), radix: 16) }
    }
}
