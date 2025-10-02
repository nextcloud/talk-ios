/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCSignalingMessage.h"

#import "WebRTC/RTCLogging.h"

#import "ARDUtilities.h"
#import "RTCIceCandidate+JSON.h"
#import "RTCSessionDescription+JSON.h"

static NSString * const kNCSignalingMessageEventKey = @"ev";
static NSString * const kNCSignalingMessageFunctionKey = @"fn";
static NSString * const kNCSignalingMessageSessionIdKey = @"sessionId";

static NSString * const kNCSignalingMessageKey = @"message";

static NSString * const kNCExternalSignalingMessageDataKey = @"data";
static NSString * const kNCExternalSignalingMessageSenderKey = @"sender";
static NSString * const kNCExternalSignalingMessageTypeSessionKey = @"session";
static NSString * const kNCExternalSignalingMessageTypeRoomKey = @"room";
static NSString * const kNCExternalSignalingMessageSessionIdKey = @"sessionid";

static NSString * const kNCSignalingMessageFromKey = @"from";
static NSString * const kNCSignalingMessageToKey = @"to";
static NSString * const kNCSignalingMessageSidKey = @"sid";
static NSString * const kNCSignalingMessageTypeKey = @"type";
static NSString * const kNCSignalingMessageActionKey = @"action";
static NSString * const kNCSignalingMessagePayloadKey = @"payload";
static NSString * const kNCSignalingMessageRoomTypeKey = @"roomType";
static NSString * const kNCSignalingMessageNickKey = @"nick";
static NSString * const kNCSignalingMessageStatusKey = @"status";
static NSString * const kNCSignalingMessageNameKey = @"name";
static NSString * const kNCSignalingMessageBroadcasterKey = @"broadcaster";

static NSString * const kNCSignalingMessageTypeOfferKey = @"offer";
static NSString * const kNCSignalingMessageTypeAnswerKey = @"answer";
static NSString * const kNCSignalingMessageTypeCandidateKey = @"candidate";
static NSString * const kNCSignalingMessageTypeUnshareScreenKey = @"unshareScreen";
static NSString * const kNCSignalingMessageTypeRemoveCandidatesKey = @"remove-candidates";
static NSString * const kNCSignalingMessageTypeControlKey = @"control";
static NSString * const kNCSignalingMessageTypeForceMuteKey = @"forceMute";
static NSString * const kNCSignalingMessageTypeMuteKey = @"mute";
static NSString * const kNCSignalingMessageTypeUnmuteKey = @"unmute";
static NSString * const kNCSignalingMessageTypeNickChangedKey = @"nickChanged";
static NSString * const kNCSignalingMessageTypeRaiseHandKey = @"raiseHand";
static NSString * const kNCSignalingMessageTypeRecordingKey = @"recording";
static NSString * const kNCSignalingMessageTypeReactionKey = @"reaction";
static NSString * const kNCSignalingMessageTypeStartedTypingKey = @"startedTyping";
static NSString * const kNCSignalingMessageTypeStoppedTypingKey = @"stoppedTyping";

static NSString * const kNCSignalingMessageSdpKey = @"sdp";

NSString *const kRoomTypeVideo = @"video";
NSString *const kRoomTypeScreen = @"screen";

@implementation NCSignalingMessage

@synthesize from = _from;
@synthesize to = _to;
@synthesize type = _type;
@synthesize payload = _payload;
@synthesize roomType = _roomType;
@synthesize sid = _sid;
@synthesize broadcaster = _broadcaster;

- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                        type:(NSString *)type
                     payload:(NSDictionary *)payload
                    roomType:(NSString *)roomType
                 broadcaster:(NSString *)broadcaster
{
    if (self = [super init]) {
        _from = from;
        _to = to;
        _sid = sid;
        _type = type;
        _payload = payload;
        _roomType = roomType;
        _broadcaster = broadcaster;
    }
    return self;
}

- (NSString *)description {
    return [[NSString alloc] initWithData:[self JSONData]
                                 encoding:NSUTF8StringEncoding];
}

+ (NCSignalingMessage *)messageFromJSONString:(NSString *)jsonString {
    NSDictionary *values = [NSDictionary dictionaryWithJSONString:jsonString];
    if (!values) {
        RTCLogError(@"Error parsing signaling message JSON.");
        return nil;
    }
    
    return [self messageFromJSONDictionary:values];
}

+ (NCSignalingMessage *)messageFromJSONDictionary:(NSDictionary *)jsonDict {
    NSString *typeString = [jsonDict objectForKey:kNCSignalingMessageTypeKey];
    NCSignalingMessage *message = nil;
    if ([typeString isEqualToString:kNCSignalingMessageTypeCandidateKey]) {
        message = [[NCICECandidateMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeOfferKey] ||
               [typeString isEqualToString:kNCSignalingMessageTypeAnswerKey]) {
        message = [[NCSessionDescriptionMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeUnshareScreenKey]) {
        message = [[NCUnshareScreenMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeControlKey]) {
        message = [[NCControlMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeMuteKey]) {
        message = [[NCMuteMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeUnmuteKey]) {
        message = [[NCUnmuteMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeNickChangedKey]) {
        message = [[NCNickChangedMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeRaiseHandKey]) {
        message = [[NCRaiseHandMessage alloc] initWithValues:jsonDict];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeReactionKey]) {
        message = [[NCReactionMessage alloc] initWithValues:jsonDict];
    } else {
        NSLog(@"Unexpected type: %@", typeString);
    }
    
    return message;
}

+ (NCSignalingMessage *)messageFromExternalSignalingJSONDictionary:(NSDictionary *)jsonDict {
    NSDictionary *data = [jsonDict objectForKey:kNCExternalSignalingMessageDataKey];
    
    NSString *dataType = [data objectForKey:kNCSignalingMessageTypeKey];
    if ([dataType isEqualToString:kNCSignalingMessageTypeUnshareScreenKey]) {
        return [[NCUnshareScreenMessage alloc] initWithValues:jsonDict];
    } else if ([dataType isEqualToString:kNCSignalingMessageTypeMuteKey]) {
        return [[NCMuteMessage alloc] initWithValues:jsonDict];
    } else if ([dataType isEqualToString:kNCSignalingMessageTypeUnmuteKey]) {
        return [[NCUnmuteMessage alloc] initWithValues:jsonDict];
    } else if ([dataType isEqualToString:kNCSignalingMessageTypeNickChangedKey]) {
        return [[NCNickChangedMessage alloc] initWithValues:jsonDict];
    } else if ([dataType isEqualToString:kNCSignalingMessageTypeRaiseHandKey]) {
        return [[NCRaiseHandMessage alloc] initWithValues:jsonDict];
    } else if ([dataType isEqualToString:kNCSignalingMessageTypeRecordingKey]) {
        return [[NCRecordingMessage alloc] initWithValues:jsonDict];
    } else if ([dataType isEqualToString:kNCSignalingMessageTypeReactionKey]) {
        return [[NCReactionMessage alloc] initWithValues:jsonDict];
    }
    
    NSString *dataAction = [data objectForKey:kNCSignalingMessageActionKey];
    if ([dataAction isEqualToString:kNCSignalingMessageTypeForceMuteKey]) {
        return [[NCControlMessage alloc] initWithValues:jsonDict];
    }
    
    NSDictionary *sender = [jsonDict objectForKey:kNCExternalSignalingMessageSenderKey];
    NSString *messageType = [sender objectForKey:kNCSignalingMessageTypeKey];
    if ([messageType isEqualToString:kNCExternalSignalingMessageTypeSessionKey]) {
        NSString *type = [data objectForKey:kNCSignalingMessageTypeKey];
        if ([type isEqualToString:kNCSignalingMessageTypeCandidateKey]) {
            return [[NCICECandidateMessage alloc] initWithValues:jsonDict];
        } else if ([type isEqualToString:kNCSignalingMessageTypeOfferKey] ||
                   [type isEqualToString:kNCSignalingMessageTypeAnswerKey]) {
            return [[NCSessionDescriptionMessage alloc] initWithValues:jsonDict];
        }
    }
    
    NSLog(@"Unexpected external signaling message: %@", jsonDict);
    return nil;
}

- (NSData *)JSONData {
    return nil;
}

- (NSDictionary *)messageDict {
    return @{};
}

- (NSDictionary *)functionDict {
    return @{};
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeUnknown;
}

+ (NSString *)getMessageSid {
    NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970];
    return [[NSNumber numberWithDouble: timeStamp] stringValue];
}

@end

@implementation NCICECandidateMessage

@synthesize candidate = _candidate;

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
    }
    RTCIceCandidate *candidate = [RTCIceCandidate candidateFromJSONDictionary:[[dataDict objectForKey:kNCSignalingMessagePayloadKey] objectForKey:kNCSignalingMessageTypeCandidateKey]];
    return [self initWithCandidate:candidate
                              from:from
                                to:[dataDict objectForKey:kNCSignalingMessageToKey]
                               sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                       broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                    options:NSJSONWritingPrettyPrinted
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }
    
    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];
    
    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    
    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
             kNCSignalingMessageEventKey: kNCSignalingMessageKey,
             kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
             kNCSignalingMessageSessionIdKey: self.from
             };
}

- (NSDictionary *)functionDict {
    return @{
             kNCSignalingMessageToKey: self.to,
             kNCSignalingMessageRoomTypeKey: self.roomType,
             kNCSignalingMessageTypeKey: self.type,
             kNCSignalingMessageSidKey: self.sid,
             kNCSignalingMessagePayloadKey: @{
                     kNCSignalingMessageTypeKey: self.type,
                     kNCSignalingMessageTypeCandidateKey: [self.candidate JSONDictionary]
                     },
             };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeCandidate;
}

- (instancetype)initWithCandidate:(RTCIceCandidate *)candidate
                             from:(NSString *)from
                               to:(NSString *)to
                              sid:(NSString *)sid
                         roomType:(NSString *)roomType
                      broadcaster:(NSString *)broadcaster
{
    NSDictionary *payload = [[NSDictionary alloc] init];
    self = [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeCandidateKey
                       payload:payload
                      roomType:roomType
                   broadcaster:broadcaster];
    
    if (!self) {
        return nil;
    }
    
    _candidate = candidate;

    return self;
}

@end

@implementation NCSessionDescriptionMessage

@synthesize sessionDescription = _sessionDescription;
@synthesize nick = _nick;

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
    }
    RTCSessionDescription *description = [RTCSessionDescription descriptionFromJSONDictionary:[dataDict objectForKey:kNCSignalingMessagePayloadKey]];
    NSString *nick = [[dataDict objectForKey:kNCSignalingMessagePayloadKey] objectForKey:kNCSignalingMessageNickKey];
    return [self initWithSessionDescription:description
                                       from:from
                                         to:[dataDict objectForKey:kNCSignalingMessageToKey]
                                        sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                                   roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                                broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]
                                       nick:nick];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self messageDict]
                                    options:0
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }
    
    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSMutableDictionary *functionData = [[NSMutableDictionary alloc] initWithDictionary:[self functionDict]];

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:functionData
                                                       options:0
                                                         error:&error];
    
    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    
    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
             kNCSignalingMessageEventKey: kNCSignalingMessageKey,
             kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
             kNCSignalingMessageSessionIdKey: self.from
             };
}

- (NSDictionary *)functionDict {
    return @{
             kNCSignalingMessageToKey: self.to,
             kNCSignalingMessageRoomTypeKey: self.roomType,
             kNCSignalingMessageTypeKey: self.type,
             kNCSignalingMessageSidKey: self.sid,
             kNCSignalingMessageBroadcasterKey: self.broadcaster ? self.broadcaster : @"",
             kNCSignalingMessagePayloadKey: @{
                     kNCSignalingMessageTypeKey: self.type,
                     kNCSignalingMessageSdpKey: self.sessionDescription.sdp,
                     kNCSignalingMessageNickKey: self.nick
                     },
             };
}

- (NCSignalingMessageType)messageType {
    if ([self.type isEqualToString:kNCSignalingMessageTypeOfferKey]) {
        return kNCSignalingMessageTypeOffer;
    }
    return kNCSignalingMessageTypeAnswer;
}

- (instancetype)initWithSessionDescription:(RTCSessionDescription *)sessionDescription
                                      from:(NSString *)from
                                        to:(NSString *)to
                                       sid:(NSString *)sid
                                  roomType:(NSString *)roomType
                               broadcaster:(NSString *)broadcaster
                                      nick:(NSString *)nick
{
    RTCSdpType sdpType = sessionDescription.type;
    NSString *type = @"";
    switch (sdpType) {
        case RTCSdpTypeOffer:
            type = kNCSignalingMessageTypeOfferKey;
            break;
        case RTCSdpTypeAnswer:
            type = kNCSignalingMessageTypeAnswerKey;
            break;
        case RTCSdpTypePrAnswer:
            NSAssert(NO, @"Unexpected type: %@",
                     [RTCSessionDescription stringForType:sdpType]);
            break;
    }
    
    NSMutableDictionary *payload = [[NSMutableDictionary alloc] init];
    [payload setObject:type forKey:kNCSignalingMessageTypeKey];
    [payload setObject:sessionDescription.sdp forKey:kNCSignalingMessageSdpKey];
    
    self = [super initWithFrom:from
                            to:to
                           sid:sid
                          type:type
                       payload:payload
                      roomType:roomType
                   broadcaster:broadcaster];
    
    if (!self) {
        return nil;
    }
    
    _sessionDescription = sessionDescription;
    _nick = nick;
    
    return self;
}

@end

@implementation NCUnshareScreenMessage

- (instancetype)initWithFrom:(NSString *)from to:(NSString *)to sid:(NSString *)sid roomType:(NSString *)roomType payload:(NSDictionary *)payload {

    return [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeUnshareScreenKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *payload = [[NSDictionary alloc] init];
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeUnshareScreenKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
        kNCSignalingMessageEventKey: kNCSignalingMessageKey,
        kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
        kNCSignalingMessageSessionIdKey: self.from
    };
}

- (NSDictionary *)functionDict {
    return @{
        kNCSignalingMessageToKey: self.to,
        kNCSignalingMessageRoomTypeKey: self.roomType,
        kNCSignalingMessageTypeKey: self.type,
        kNCSignalingMessageSidKey: self.sid,
        kNCSignalingMessagePayloadKey: self.payload,
    };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeUnshareScreen;
}

@end

@implementation NCControlMessage

- (instancetype)initWithFrom:(NSString *)from to:(NSString *)to sid:(NSString *)sid roomType:(NSString *)roomType payload:(NSDictionary *)payload {

    return [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeControlKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = dataDict;
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeControlKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self messageDict]
                                    options:0
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
        kNCSignalingMessageEventKey: kNCSignalingMessageKey,
        kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
        kNCSignalingMessageSessionIdKey: self.from
    };
}

- (NSDictionary *)functionDict {
    return @{
        kNCSignalingMessageToKey: self.to,
        kNCSignalingMessageRoomTypeKey: self.roomType,
        kNCSignalingMessageTypeKey: self.type,
        kNCSignalingMessageSidKey: self.sid,
        kNCSignalingMessagePayloadKey: self.payload,
    };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeControl;
}

@end

@implementation NCMuteMessage

- (instancetype)initWithFrom:(NSString *)from to:(NSString *)to sid:(NSString *)sid roomType:(NSString *)roomType payload:(NSDictionary *)payload {

    return [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeMuteKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeMuteKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                    options:NSJSONWritingPrettyPrinted
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
             kNCSignalingMessageEventKey: kNCSignalingMessageKey,
             kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
             kNCSignalingMessageSessionIdKey: self.from
             };
}

- (NSDictionary *)functionDict {
    return @{
             kNCSignalingMessageToKey: self.to,
             kNCSignalingMessageRoomTypeKey: self.roomType,
             kNCSignalingMessageTypeKey: self.type,
             kNCSignalingMessageSidKey: self.sid,
             kNCSignalingMessagePayloadKey: self.payload,
             };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeMute;
}

@end

@implementation NCUnmuteMessage

- (instancetype)initWithFrom:(NSString *)from to:(NSString *)to sid:(NSString *)sid roomType:(NSString *)roomType payload:(NSDictionary *)payload {

    return [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeUnmuteKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeUnmuteKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                    options:NSJSONWritingPrettyPrinted
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
             kNCSignalingMessageEventKey: kNCSignalingMessageKey,
             kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
             kNCSignalingMessageSessionIdKey: self.from
             };
}

- (NSDictionary *)functionDict {
    return @{
             kNCSignalingMessageToKey: self.to,
             kNCSignalingMessageRoomTypeKey: self.roomType,
             kNCSignalingMessageTypeKey: self.type,
             kNCSignalingMessageSidKey: self.sid,
             kNCSignalingMessagePayloadKey: self.payload,
             };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeUnmute;
}

@end

@implementation NCNickChangedMessage

- (instancetype)initWithFrom:(NSString *)from to:(NSString *)to sid:(NSString *)sid roomType:(NSString *)roomType payload:(NSDictionary *)payload {

    return [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeNickChangedKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeNickChangedKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                    options:NSJSONWritingPrettyPrinted
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
        kNCSignalingMessageEventKey: kNCSignalingMessageKey,
        kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
        kNCSignalingMessageSessionIdKey: self.from
    };
}

- (NSDictionary *)functionDict {
    return @{
        kNCSignalingMessageToKey: self.to,
        kNCSignalingMessageRoomTypeKey: self.roomType,
        kNCSignalingMessageTypeKey: self.type,
        kNCSignalingMessageSidKey: self.sid,
        kNCSignalingMessagePayloadKey: self.payload,
    };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeNickChanged;
}

@end

@implementation NCRaiseHandMessage

- (instancetype)initWithFrom:(NSString *)from to:(NSString *)to sid:(NSString *)sid roomType:(NSString *)roomType payload:(NSDictionary *)payload {

    return [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeRaiseHandKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeRaiseHandKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self messageDict]
                                    options:0
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
             kNCSignalingMessageEventKey: kNCSignalingMessageKey,
             kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
             kNCSignalingMessageSessionIdKey: self.from
             };
}

- (NSDictionary *)functionDict {
    return @{
             kNCSignalingMessageToKey: self.to,
             kNCSignalingMessageRoomTypeKey: self.roomType,
             kNCSignalingMessageTypeKey: self.type,
             kNCSignalingMessageSidKey: self.sid,
             kNCSignalingMessagePayloadKey: self.payload,
             };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeRaiseHand;
}

@end

@implementation NCRecordingMessage

@synthesize status = _status;

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *valuesDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *dataDict = [valuesDict objectForKey:kNCExternalSignalingMessageDataKey];
    NSDictionary *recordingDict = [dataDict objectForKey:kNCSignalingMessageTypeRecordingKey];

    self = [super initWithFrom:nil
                            to:nil
                           sid:nil
                          type:kNCSignalingMessageTypeRecordingKey
                       payload:recordingDict
                      roomType:nil
                   broadcaster:nil];
    if (self) {
        _status = [[recordingDict objectForKey:kNCSignalingMessageStatusKey] integerValue];
    }

    return self;
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeRecording;
}

@end

@implementation NCReactionMessage

- (instancetype)initWithFrom:(NSString *)from to:(NSString *)to sid:(NSString *)sid roomType:(NSString *)roomType payload:(NSDictionary *)payload {

    return [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeReactionKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeReactionKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self messageDict]
                                    options:0
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
             kNCSignalingMessageEventKey: kNCSignalingMessageKey,
             kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
             kNCSignalingMessageSessionIdKey: self.from
             };
}

- (NSDictionary *)functionDict {
    return @{
             kNCSignalingMessageToKey: self.to,
             kNCSignalingMessageRoomTypeKey: self.roomType,
             kNCSignalingMessageTypeKey: self.type,
             kNCSignalingMessageSidKey: self.sid,
             kNCSignalingMessagePayloadKey: self.payload,
             };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeReaction;
}

@end


@implementation NCStartedTypingMessage

- (instancetype)initWithFrom:(NSString *)from sendTo:(NSString *)to withPayload:(NSDictionary *)payload forRoomType:(NSString *)roomType {

    return [super initWithFrom:from
                            to:to
                           sid:[NCSignalingMessage getMessageSid]
                          type:kNCSignalingMessageTypeStartedTypingKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeStartedTypingKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self messageDict]
                                    options:0
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
        kNCSignalingMessageEventKey: kNCSignalingMessageKey,
        kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
        kNCSignalingMessageSessionIdKey: self.from
    };
}

- (NSDictionary *)functionDict {
    return @{
        kNCSignalingMessageToKey: self.to,
        kNCSignalingMessageRoomTypeKey: self.roomType,
        kNCSignalingMessageTypeKey: self.type,
        kNCSignalingMessagePayloadKey: self.payload,
    };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeStartedTyping;
}

@end

@implementation NCStoppedTypingMessage

- (instancetype)initWithFrom:(NSString *)from sendTo:(NSString *)to withPayload:(NSDictionary *)payload forRoomType:(NSString *)roomType {

    return [super initWithFrom:from
                            to:to
                           sid:[NCSignalingMessage getMessageSid]
                          type:kNCSignalingMessageTypeStoppedTypingKey
                       payload:payload
                      roomType:roomType
                   broadcaster:nil];
}

- (instancetype)initWithValues:(NSDictionary *)values {
    NSDictionary *dataDict = [[NSDictionary alloc] initWithDictionary:values];
    NSDictionary *payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    NSString *from = [values objectForKey:kNCSignalingMessageFromKey];
    // Get 'from' value from 'sender' using External Signaling
    NSDictionary *sender = [values objectForKey:kNCExternalSignalingMessageSenderKey];
    if (sender) {
        from = [sender objectForKey:kNCExternalSignalingMessageSessionIdKey];
        dataDict = [values objectForKey:kNCExternalSignalingMessageDataKey];
        payload = [dataDict objectForKey:kNCSignalingMessagePayloadKey];
    }
    return [super initWithFrom:from
                            to:[dataDict objectForKey:kNCSignalingMessageToKey]
                           sid:[dataDict objectForKey:kNCSignalingMessageSidKey]
                          type:kNCSignalingMessageTypeStoppedTypingKey
                       payload:payload
                      roomType:[dataDict objectForKey:kNCSignalingMessageRoomTypeKey]
                   broadcaster:[dataDict objectForKey:kNCSignalingMessageBroadcasterKey]];
}

- (NSData *)JSONData {
    NSError *error = nil;
    NSData *data =
    [NSJSONSerialization dataWithJSONObject:[self messageDict]
                                    options:0
                                      error:&error];
    if (error) {
        RTCLogError(@"Error serializing JSON: %@", error);
        return nil;
    }

    return data;
}

- (NSString *)functionJSONSerialization
{
    NSError *error;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self functionDict]
                                                       options:0
                                                         error:&error];

    if (! jsonData) {
        NSLog(@"Error serializing JSON: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    return jsonString;
}

- (NSDictionary *)messageDict {
    return @{
        kNCSignalingMessageEventKey: kNCSignalingMessageKey,
        kNCSignalingMessageFunctionKey: [self functionJSONSerialization],
        kNCSignalingMessageSessionIdKey: self.from
    };
}

- (NSDictionary *)functionDict {
    return @{
        kNCSignalingMessageToKey: self.to,
        kNCSignalingMessageRoomTypeKey: self.roomType,
        kNCSignalingMessageTypeKey: self.type,
        kNCSignalingMessagePayloadKey: self.payload,
    };
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeStoppedTyping;
}

@end
