//
/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#ifndef CallConstants_h
#define CallConstants_h

typedef NS_OPTIONS(NSInteger, CallFlag) {
    CallFlagDisconnected = 0,
    CallFlagInCall = 1,
    CallFlagWithAudio = 2,
    CallFlagWithVideo = 4,
    CallFlagWithPhone = 8
};

typedef NS_ENUM(NSInteger, CallState) {
    CallStateJoining,
    CallStateWaitingParticipants,
    CallStateReconnecting,
    CallStateInCall,
    CallStateSwitchingToAnotherRoom
};

typedef NS_ENUM(NSInteger, NCParticipantType) {
    kNCParticipantTypeUnknown = 0,
    kNCParticipantTypeOwner,
    kNCParticipantTypeModerator,
    kNCParticipantTypeUser,
    kNCParticipantTypeGuest,
    kNCParticipantTypeUserSelfJoined,
    kNCParticipantTypeGuestModerator
};

#endif /* CallConstants_h */
