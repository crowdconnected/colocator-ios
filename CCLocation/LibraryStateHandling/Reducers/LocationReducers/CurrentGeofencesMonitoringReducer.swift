//
//  CurrentGeofencesMonitoringReducer.swift
//  CCLocation
//
//  Created by Mobile Developer on 20/08/2019.
//  Copyright © 2019 Crowd Connected. All rights reserved.
//

import ReSwift

private struct CurrentGeofencesMonitorinReducerConstants {
    static let userDefaultsCurrentGeofencesMonitoringKey = "currentGeofencesMonitoringKey"
}

private typealias C = CurrentGeofencesMonitorinReducerConstants

func currentGeofencesMonitoringReducer (action: Action, state: CurrentGeofencesMonitoringState?) -> CurrentGeofencesMonitoringState {
    var state = state ?? CurrentGeofencesMonitoringState(monitoringGeofences: [])
   
    if action is DisableGeofencesMonitoringAction {
        state.monitoringGeofences = []
    }
    
    return state
}

private func getCurrentStateFromUserDefaults () -> CurrentGeofencesMonitoringState? {
    let userDefaults = UserDefaults.standard
    let value = userDefaults.string(forKey: C.userDefaultsCurrentGeofencesMonitoringKey)
    
    if value != nil {
        return CurrentGeofencesMonitoringState(monitoringGeofences: [])
    } else {
        return nil
    }
}

private func saveCurrentStateToUserDefaults (currentGEOState: CurrentGeofencesMonitoringState){
}
