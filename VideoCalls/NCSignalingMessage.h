//
//  NCSignalingMessage.h
//  VideoCalls
//
//  Created by Ivan Sein on 04.08.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "WebRTC/RTCIceCandidate.h"
#import "WebRTC/RTCSessionDescription.h"

typedef enum {
    kNCSignalingMessageTypeUknown,
    kNCSignalingMessageTypeCandidate,
    kNCSignalingMessageTypeOffer,
    kNCSignalingMessageTypeAnswer,
} NCSignalingMessageType;


@interface NCSignalingMessage : NSObject

@property(nonatomic, readonly) NSString *from;
@property(nonatomic, readonly) NSString *to;
@property(nonatomic, readonly) NSString *sid;
@property(nonatomic, readonly) NSString *type;
@property(nonatomic, readonly) NSDictionary *payload;
@property(nonatomic, readonly) NSString *roomType;

+ (NCSignalingMessage *)messageFromJSONString:(NSString *)jsonString;
+ (NSString *)getMessageSid;
- (NSDictionary *)messageDict;
- (NCSignalingMessageType)messageType;

@end

@interface NCICECandidateMessage : NCSignalingMessage

@property(nonatomic, readonly) RTCIceCandidate *candidate;

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithCandidate:(RTCIceCandidate *)candidate
                             from:(NSString *)from
                               to:(NSString *)to
                              sid:(NSString *)sid
                         roomType:(NSString *)roomType;

@end

@interface NCSessionDescriptionMessage : NCSignalingMessage

@property(nonatomic, readonly) RTCSessionDescription *sessionDescription;

- (instancetype)initWithValues:(NSDictionary *)values;
- (instancetype)initWithSessionDescription:(RTCSessionDescription *)sessionDescription
                                      from:(NSString *)from
                                        to:(NSString *)to
                                       sid:(NSString *)sid
                                  roomType:(NSString *)roomType;


@end

