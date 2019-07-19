//
//  BackgroundiBeaconReducer.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 01/08/2017.
//  Copyright © 2017 Crowd Connected. All rights reserved.
//

import ReSwift
import CoreLocation

private struct BackgroundiBeaconReducerConstants {
    static let userDefaultsBackgroundiBeaconKey = "bGiBeaconKey"
    static let userDefaultsBackgroundiBeaconRegionsKey = "bGiBeaconRegionsKey"
    static let userDefaultsBackgroundiBeaconFilterRegionsKey = "bGiBeaconFilterRegionsKey"
}

private typealias C = BackgroundiBeaconReducerConstants

func backgroundiBeaconReducer (action: Action, state: BackgroundBeaconState?) -> BackgroundBeaconState {
    
    var bGiBeaconState = BackgroundBeaconState(bGiBeaconEnabled: false, maxRuntime: nil, minOffTime: nil, regions: [], filterWindowSize: nil, filterMaxObservations: nil, filterExcludeRegions: [], eddystoneScanEnabled: false)
    
    if let loadedbGiBeaconState = getBackgroundiBeaconStateFromUserDefaults() {
        bGiBeaconState = loadedbGiBeaconState
    }
    
    var state = state ?? bGiBeaconState
    
    switch action {
    case let enableBackgroundiBeaconAction as EnableBackgroundiBeaconAction:
        
        state.maxRuntime = enableBackgroundiBeaconAction.maxRuntime
        state.minOffTime = enableBackgroundiBeaconAction.minOffTime
       
        state.regions = enableBackgroundiBeaconAction.regions
        
        state.filterWindowSize = enableBackgroundiBeaconAction.filterWindowSize
        state.filterMaxObservations = enableBackgroundiBeaconAction.filterMaxObservations
        
        state.filterExcludeRegions = enableBackgroundiBeaconAction.filterExcludeRegions

        state.isEddystoneScanningEnabled = enableBackgroundiBeaconAction.isEddystoneScanningEnabled
        
        state.isIBeaconRangingEnabled = enableBackgroundiBeaconAction.isIBeaconRangingEnabled
        
        saveBackgroundiBeaconStateToUserDefaults(iBeaconState: state)
        
    case _ as DisableBackgroundiBeaconAction:
        state.isIBeaconRangingEnabled = false

        saveBackgroundiBeaconStateToUserDefaults(iBeaconState: state)
        
    default:
        break
    }
    return state
}

private func getBackgroundiBeaconStateFromUserDefaults () -> BackgroundBeaconState? {
    let userDefaults = UserDefaults.standard
    
    var bGIBeaconState:BackgroundBeaconState?
    
    if let iBeaconDictionary = userDefaults.dictionary(forKey: C.userDefaultsBackgroundiBeaconKey){
        
        if bGIBeaconState == nil {
            bGIBeaconState = BackgroundBeaconState(bGiBeaconEnabled: false, maxRuntime: nil, minOffTime: nil, regions: [], filterWindowSize: nil, filterMaxObservations: nil, filterExcludeRegions: [], eddystoneScanEnabled: false)
        }
        
        bGIBeaconState?.maxRuntime = iBeaconDictionary["maxRuntime"] as? UInt64
        bGIBeaconState?.minOffTime = iBeaconDictionary["minOffTime"] as? UInt64
        bGIBeaconState?.filterWindowSize = iBeaconDictionary["filterWindowSize"] as? UInt64
        bGIBeaconState?.filterMaxObservations = iBeaconDictionary["filterMaxObservations"] as? UInt32
        bGIBeaconState?.isEddystoneScanningEnabled = iBeaconDictionary["isEddystoneScanningEnabled"] as? Bool
        bGIBeaconState?.isIBeaconRangingEnabled = iBeaconDictionary["bGiBeaconEnabled"] as? Bool
    }
    
    if let decoded = userDefaults.object(forKey: C.userDefaultsBackgroundiBeaconRegionsKey) as? Data {
        
        if bGIBeaconState == nil {
            bGIBeaconState = BackgroundBeaconState(bGiBeaconEnabled: false, maxRuntime: nil, minOffTime: nil, regions: [], filterWindowSize: nil, filterMaxObservations: nil, filterExcludeRegions: [], eddystoneScanEnabled: false)
        }
        
        let decodediBeaconRegions = NSKeyedUnarchiver.unarchiveObject(with: decoded) as? [CLBeaconRegion] ?? [CLBeaconRegion] ()
        
        bGIBeaconState?.regions = decodediBeaconRegions
    }
    
    if let decoded = userDefaults.object(forKey: C.userDefaultsBackgroundiBeaconFilterRegionsKey) as? Data {
        
        if bGIBeaconState == nil {
            bGIBeaconState = BackgroundBeaconState(bGiBeaconEnabled: false, maxRuntime: nil, minOffTime: nil, regions: [], filterWindowSize: nil, filterMaxObservations: nil, filterExcludeRegions: [], eddystoneScanEnabled: false)
        }
        
        let decodediBeaconFilteredRegions = NSKeyedUnarchiver.unarchiveObject(with: decoded) as? [CLBeaconRegion] ?? [CLBeaconRegion] ()
        
        bGIBeaconState?.filterExcludeRegions = decodediBeaconFilteredRegions
    }
    
    return bGIBeaconState
}

private func saveBackgroundiBeaconStateToUserDefaults (iBeaconState: BackgroundBeaconState?) {
    guard let iBeaconState = iBeaconState else {
        return
    }
    
    let userDefaults = UserDefaults.standard
    
    var dictionary = setupCommonBeaconDictionary(forBeaconState: iBeaconState)
  
    userDefaults.set(dictionary, forKey: C.userDefaultsBackgroundiBeaconKey)
    
    let encodedRegions = NSKeyedArchiver.archivedData(withRootObject: iBeaconState.regions)
    
    userDefaults.set(encodedRegions, forKey: C.userDefaultsBackgroundiBeaconRegionsKey)
    
    let encodedFilterRegions = NSKeyedArchiver.archivedData(withRootObject: iBeaconState.filterExcludeRegions)
    
    userDefaults.set(encodedFilterRegions, forKey: C.userDefaultsBackgroundiBeaconFilterRegionsKey)
    
    userDefaults.synchronize()
}

func setupCommonBeaconDictionary(forBeaconState iBeaconState: BackgroundBeaconState) -> Dictionary<String, Int64> {
    var dictionary = [String:Int64]()
    
    if let maxRuntime = iBeaconState.maxRuntime {
        dictionary["maxRuntime"] = Int64(maxRuntime)
    }
    
    if let minOffTime = iBeaconState.minOffTime {
        dictionary["minOffTime"] = Int64(minOffTime)
    }
    
    if let filterWindowSize = iBeaconState.filterWindowSize {
        dictionary["filterWindowSize"] = Int64(filterWindowSize)
    }
    
    if let filterMaxObservations = iBeaconState.filterMaxObservations {
        dictionary["filterMaxObservations"] = Int64(filterMaxObservations)
    }
    
    if let eddystoneScan = iBeaconState.isEddystoneScanningEnabled {
        dictionary["isEddystoneScanEnabled"] = eddystoneScan ? 1 : 0
    }
    
    if let bGiBeaconEnabled = iBeaconState.isIBeaconRangingEnabled {
        dictionary["bGiBeaconEnabled"] = bGiBeaconEnabled ? 1 : 0
    }
    
    return dictionary
}
