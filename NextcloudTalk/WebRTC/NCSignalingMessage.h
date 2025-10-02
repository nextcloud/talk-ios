/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "WebRTC/RTCIceCandidate.h"
#import "WebRTC/RTCSessionDescription.h"

extern NSString *const kRoomTypeVideo;
extern NSString *const kRoomTypeScreen;

typedef NS_ENUM(NSInteger, NCSignalingMessageType) {
    kNCSignalingMessageTypeUnknown,
    kNCSignalingMessageTypeCandidate,
    kNCSignalingMessageTypeOffer,
    kNCSignalingMessageTypeAnswer,
    kNCSignalingMessageTypeUnshareScreen,
    kNCSignalingMessageTypeControl,
    kNCSignalingMessageTypeMute,
    kNCSignalingMessageTypeUnmute,
    kNCSignalingMessageTypeNickChanged,
    kNCSignalingMessageTypeRaiseHand,
    kNCSignalingMessageTypeRecording,
    kNCSignalingMessageTypeReaction,
    kNCSignalingMessageTypeStartedTyping,
    kNCSignalingMessageTypeStoppedTyping
};


@interface NCSignalingMessage : NSObject

@property(nonatomic, readonly) NSString *from;
@property(nonatomic, readonly) NSString *to;
@property(nonatomic, readonly) NSString *sid;
@property(nonatomic, readonly) NSString *type;
@property(nonatomic, readonly) NSDictionary *payload;
@property(nonatomic, readonly) NSString *roomType;
@property(nonatomic, assign) NSString *broadcaster;

+ (NCSignalingMessage *)messageFromJSONString:(NSString *)jsonString;
+ (NCSignalingMessage *)messageFromJSONDictionary:(NSDictionary *)jsonDict;
+ (NCSignalingMessage *)messageFromExternalSignalingJSONDictionary:(NSDictionary *)jsonDict;
+ (NSString *)getMessageSid;
- (NSDictionary *)messageDict;
- (NSDictionary *)functionDict;
- (NCSignalingMessageType)messageType;

@end

@interface NCICECandidateMessage : NCSignalingMessage

@property(nonatomic, readonly) RTCIceCandidate *candidate;

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithCandidate:(RTCIceCandidate *)candidate
                             from:(NSString *)from
                               to:(NSString *)to
                              sid:(NSString *)sid
                         roomType:(NSString *)roomType
                      broadcaster:(NSString *)broadcaster;

@end

@interface NCSessionDescriptionMessage : NCSignalingMessage

@property(nonatomic, readonly) RTCSessionDescription *sessionDescription;
@property(nonatomic, readonly) NSString *nick;

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithSessionDescription:(RTCSessionDescription *)sessionDescription
                                      from:(NSString *)from
                                        to:(NSString *)to
                                       sid:(NSString *)sid
                                  roomType:(NSString *)roomType
                               broadcaster:(NSString *)broadcaster
                                      nick:(NSString *)nick;


@end

@interface NCUnshareScreenMessage : NCSignalingMessage

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                    roomType:(NSString *)roomType
                     payload:(NSDictionary *)payload;

@end

@interface NCControlMessage : NCSignalingMessage

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                    roomType:(NSString *)roomType
                     payload:(NSDictionary *)payload;

@end

@interface NCMuteMessage : NCSignalingMessage

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                    roomType:(NSString *)roomType
                     payload:(NSDictionary *)payload;

@end

@interface NCUnmuteMessage : NCSignalingMessage

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                    roomType:(NSString *)roomType
                     payload:(NSDictionary *)payload;

@end

@interface NCNickChangedMessage : NCSignalingMessage

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                    roomType:(NSString *)roomType
                     payload:(NSDictionary *)payload;

@end

@interface NCRaiseHandMessage : NCSignalingMessage

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                    roomType:(NSString *)roomType
                     payload:(NSDictionary *)payload;

@end

@interface NCRecordingMessage : NCSignalingMessage

@property(nonatomic, readonly) NSInteger status;

- (instancetype)initWithValues:(NSDictionary *)values;

@end

@interface NCReactionMessage : NCSignalingMessage

@property(nonatomic, readonly) NSString *reaction;

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                    roomType:(NSString *)roomType
                     payload:(NSDictionary *)payload;

@end

@interface NCStartedTypingMessage : NCSignalingMessage

- (instancetype)initWithFrom:(NSString *)from
                      sendTo:(NSString *)to
                 withPayload:(NSDictionary *)payload
                 forRoomType:(NSString *)roomType;

- (instancetype)initWithValues:(NSDictionary *)values;

@end

@interface NCStoppedTypingMessage : NCSignalingMessage

- (instancetype)initWithFrom:(NSString *)from
                      sendTo:(NSString *)to
                 withPayload:(NSDictionary *)payload
                 forRoomType:(NSString *)roomType;

- (instancetype)initWithValues:(NSDictionary *)values;

@end
