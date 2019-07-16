//
//  CCRquestMessagingReducers.swift
//  CCLocation
//
//  Created by Ralf Kernchen on 06/08/2017.
//  Copyright © 2017 Crowd Connected. All rights reserved.
//

import ReSwift

func ccRequestMessagingReducer(action: Action, state: CCRequestMessagingState?) -> CCRequestMessagingState {
    var state = CCRequestMessagingState (
        webSocketState: webSocketReducer(action: action, state: state?.webSocketState),
        radiosilenceTimerState: timerReducer(action: action, state: state?.radiosilenceTimerState),
        libraryTimeState: libraryTimeReducer(action: action, state: state?.libraryTimeState),
        capabilityState: capabilityReducer(action: action, state: state?.capabilityState)
    )
   
    switch action {
    case _ as ReSwiftInit:
        break

    // handling timer events
    case let radioSilenceTimerAction as TimeBetweenSendsTimerReceivedAction:
        
        if let timeInterval = radioSilenceTimerAction.timeInMilliseconds {
            if state.radiosilenceTimerState!.timeInterval != timeInterval {
                state.radiosilenceTimerState!.timeInterval = timeInterval
                
                state.radiosilenceTimerState!.timer = CCTimer.invalidate
                
                if state.radiosilenceTimerState!.timeInterval != nil {
                    state.radiosilenceTimerState!.timer = CCTimer.schedule
                }
                
            } else {
                //do nothing
            }
        } else {
            state.radiosilenceTimerState?.timer = CCTimer.invalidate
            state.radiosilenceTimerState?.timeInterval = nil
            state.radiosilenceTimerState?.startTimeInterval = nil
            
        }
                
        saveTimerStateToUserDefaults(timerState: state.radiosilenceTimerState)

    case let timerRunningAction as TimerRunningAction:
        state.radiosilenceTimerState?.timer = CCTimer.running

        // only set a new timer when the start time interval is nil, this is an intentional case for the starttimer
        if timerRunningAction.startTimeInterval != nil {
            state.radiosilenceTimerState?.startTimeInterval = timerRunningAction.startTimeInterval
        } else {
            state.radiosilenceTimerState?.startTimeInterval = nil
        }

    case _ as TimerStoppedAction:
        state.radiosilenceTimerState?.timer = CCTimer.stopped
        
    case _ as ScheduleSilencePeriodTimerAction:
        
        // only schedule, if we actually have a time interval available
        if (state.radiosilenceTimerState?.timeInterval != nil) {
            state.radiosilenceTimerState?.timer = CCTimer.schedule
        }
        
    default:
        break
    }

    return state
}
