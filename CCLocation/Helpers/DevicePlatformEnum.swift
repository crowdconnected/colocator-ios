//
//  DevicePlatformEnum.swift
//  CCLocation
//
//  Created by Mobile Developer on 10/07/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import Foundation

enum DevicePlatform: String {
    
    /* Source
     https://github.com/devicekit/DeviceKit/blob/master/Source/Device.swift.gyb
     */
    
    /* iPhone */
    case iPhone11 = "iPhone1,1"
    case iPhone12 = "iPhone1,2"
    case iPhone21 = "iPhone2,1"
    case iPhone31 = "iPhone3,1"
    case iPhone33 = "iPhone3,3"
    case iPhone41 = "iPhone4,1"
    case iPhone51 = "iPhone5,1"
    case iPhone52 = "iPhone5,2"
    case iPhone53 = "iPhone5,3"
    case iPhone54 = "iPhone5,4"
    case iPhone61 = "iPhone6,1"
    case iPhone62 = "iPhone6,2"
    
    case iPhone71 = "iPhone7,1"
    case iPhone72 = "iPhone7,2"
    case iPhone81 = "iPhone8,1"
    case iPhone82 = "iPhone8,2"
    case iPhone84 = "iPhone8,4"
    
    case iPhone91 = "iPhone9,1"
    case iPhone93 = "iPhone9,3"
    case iPhone92 = "iPhone9,2"
    case iPhone94 = "iPhone9,4"
    
    case iPhone101 = "iPhone10,1"
    case iPhone104 = "iPhone10,4"
    case iPhone102 = "iPhone10,2"
    case iPhone105 = "iPhone10,5"
    
    case iPhone103 = "iPhone10,3"
    case iPhone106 = "iPhone10,6"
    
    /* iPod */
    case iPod11 = "iPod1,1"
    case iPod21 = "iPod2,1"
    case iPod31 = "iPod3,1"
    case iPod41 = "iPod4,1"
    case iPod51 = "iPod5,1"
    case iPod71 = "iPod7,1"
    
    /* iPad */
    case iPad11 = "iPad1,1"
    case iPad21 = "iPad2,1"
    case iPad22 = "iPad2,2"
    case iPad23 = "iPad2,3"
    case iPad24 = "iPad2,4"
    case iPad25 = "iPad2,5"
    case iPad26 = "iPad2,6"
    case iPad27 = "iPad2,7"
    case iPad31 = "iPad3,1"
    case iPad32 = "iPad3,2"
    case iPad33 = "iPad3,3"
    case iPad34 = "iPad3,4"
    case iPad35 = "iPad3,5"
    case iPad36 = "iPad3,6"
    case iPad41 = "iPad4,1"
    case iPad42 = "iPad4,2"
    case iPad44 = "iPad4,4"
    case iPad45 = "iPad4,5"
    
    case iPad46 = "iPad4,6"
    case iPad47 = "iPad4,7"
    case iPad48 = "iPad4,8"
    case iPad49 = "iPad4,9"
    case iPad51 = "iPad5,1"
    case iPad52 = "iPad5,2"
    case iPad53 = "iPad5,3"
    case iPad54 = "iPad5,4"
    case iPad63 = "iPad6,3"
    case iPad64 = "iPad6,4"
    case iPad67 = "iPad6,7"
    case iPad68 = "iPad6,8"
    
    case iPad611 = "iPad6,11"
    case iPad612 = "iPad6,12"
    case iPad71 = "iPad7,1"
    case iPad72 = "iPad7,2"
    case iPad73 = "iPad7,3"
    case iPad74 = "iPad7,4"
    
    /* Simulator */
    case i386 = "i386"
    case x86_64 = "x86_64"

    var title: String {
        switch self {
        case .iPhone11: return "iPhone_1G"
        case .iPhone12: return "iPhone_3G"
        case .iPhone21: return "iPhone_3GS"
        case .iPhone31: return "iPhone_4"
        case .iPhone33: return "Verizon_iPhone_4"
        case .iPhone41: return "iPhone_4S"
        case .iPhone51: return "iPhone_5-GSM"
        case .iPhone52: return "iPhone_5-GSM+CDMA"
        case .iPhone53: return "iPhone_5c-GSM"
        case .iPhone54: return "iPhone_5c-GSM_CDMA"
        case .iPhone61: return "iPhone_5s-GSM"
        case .iPhone62: return "iPhone_5s-GSM_CDMA"
        case .iPhone71: return "iPhone_6_Plus"
        case .iPhone72: return "iPhone_6"
        case .iPhone81: return "iPhone_6s"
        case .iPhone82: return "iPhone_6s_Plus"
        case .iPhone84: return "iPhone_SE"
        case .iPhone91: return "iPhone_7_(Global)"
        case .iPhone93: return "iPhone_7_(GSM)"
        case .iPhone92: return "iPhone_7_Plus_(Global)"
        case .iPhone94: return "iPhone_7_Plus_(GSM)"
        case .iPhone101: return "iPhone_8"
        case .iPhone104: return "iPhone_8"
        case .iPhone102: return "iPhone_8_Plus"
        case .iPhone105: return "iPhone_8_Plus"
        case .iPhone103: return "iPhone_X"
        case .iPhone106: return "iPhone_X"
            
        case .iPod11: return "iPod_Touch_1G"
        case .iPod21: return "iPod_Touch_2G"
        case .iPod31: return "iPod_Touch_3G"
        case .iPod41: return "iPod_Touch_4G"
        case .iPod51: return "iPod_Touch_5G"
        case .iPod71: return "iPod_Touch_6G"
            
        case .iPad11: return "iPad"
        case .iPad21: return "iPad_2-WiFi"
        case .iPad22: return "iPad_2-GSM"
        case .iPad23: return "iPad_2-CDMA"
        case .iPad24: return "iPad_2-WiFi"
        case .iPad25:return "iPad_Mini-WiFi"
        case .iPad26: return "iPad_Mini-GSM"
        case .iPad27: return "iPad_Mini-GSM_CDMA)"
        case .iPad31: return "iPad_3-WiFi"
        case .iPad32: return "iPad_3-GSM_CDMA"
        case .iPad33: return "iPad_3-GSM"
        case .iPad34: return "iPad_4-WiFi"
        case .iPad35: return "iPad_4-GSM"
        case .iPad36: return "iPad_4-GSM_CDMA"
        case .iPad41: return "iPad_Air-WiFi"
        case .iPad42: return "iPad_Air-Cellular"
        case .iPad44: return "iPad_mini_2G-WiFi"
        case .iPad45: return "iPad_mini_2G-Cellular"
        case .iPad46: return "iPad_Mini_2"
        case .iPad47: return "iPad_Mini_3"
        case .iPad48: return "iPad_Mini_3"
        case .iPad49: return "iPad_Mini_3"
        case .iPad51: return "iPad_Mini_4_(WiFi)"
        case .iPad52: return "iPad_Mini_4_(LTE)"
        case .iPad53: return "iPad_Air_2"
        case .iPad54: return "iPad_Air_2"
        case .iPad63: return "iPad_Pro_9.7"
        case .iPad64: return "iPad_Pro_9.7"
        case .iPad67: return "iPad_Pro_12.9"
        case .iPad68: return "iPad_Pro_12.9"
        case .iPad611: return "iPad_5G"
        case .iPad612: return "iPad_5G"
        case .iPad71: return "iPad_Pro_12.9_2G"
        case .iPad72: return "iPad_Pro_12.9_2G"
        case .iPad73:return "iPad_Pro_10.5"
        case .iPad74: return "iPad_Pro_10.5"
            
        case .i386: return "Simulator"
        case .x86_64: return "Simulator"
        }
    }
}
