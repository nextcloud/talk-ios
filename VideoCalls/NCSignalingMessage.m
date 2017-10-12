//
//  NCSignalingMessage.m
//  VideoCalls
//
//  Created by Ivan Sein on 04.08.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCSignalingMessage.h"

#import "WebRTC/RTCLogging.h"

#import "ARDUtilities.h"
#import "RTCIceCandidate+JSON.h"
#import "RTCSessionDescription+JSON.h"

static NSString * const kNCSignalingMessageEventKey = @"ev";
static NSString * const kNCSignalingMessageFunctionKey = @"fn";
static NSString * const kNCSignalingMessageSessionIdKey = @"sessionId";

static NSString * const kNCSignalingMessageKey = @"message";
static NSString * const kNCSignalingMessageDataKey = @"data";

static NSString * const kNCSignalingMessageFromKey = @"from";
static NSString * const kNCSignalingMessageToKey = @"to";
static NSString * const kNCSignalingMessageSidKey = @"sid";
static NSString * const kNCSignalingMessageTypeKey = @"type";
static NSString * const kNCSignalingMessagePayloadKey = @"payload";
static NSString * const kNCSignalingMessageRoomTypeKey = @"roomType";
static NSString * const kNCSignalingMessageNickKey = @"nick";

static NSString * const kNCSignalingMessageTypeOfferKey = @"offer";
static NSString * const kNCSignalingMessageTypeAnswerKey = @"answer";
static NSString * const kNCSignalingMessageTypeCandidateKey = @"candidate";
static NSString * const kNCSignalingMessageTypeRemoveCandidatesKey = @"remove-candidates";

static NSString * const kNCSignalingMessageSdpKey = @"sdp";

@implementation NCSignalingMessage

@synthesize from = _from;
@synthesize to = _to;
@synthesize type = _type;
@synthesize payload = _payload;
@synthesize roomType = _roomType;
@synthesize sid = _sid;

- (instancetype)initWithFrom:(NSString *)from
                          to:(NSString *)to
                         sid:(NSString *)sid
                        type:(NSString *)type
                     payload:(NSDictionary *)payload
                    roomType:(NSString *)roomType
{
    if (self = [super init]) {
        _from = from;
        _to = to;
        _sid = sid;
        _type = type;
        _payload = payload;
        _roomType = roomType;
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
    
    NSString *typeString = values[kNCSignalingMessageTypeKey];
    NCSignalingMessage *message = nil;
    if ([typeString isEqualToString:kNCSignalingMessageTypeCandidateKey]) {
        message = [[NCICECandidateMessage alloc] initWithValues:values];
    } else if ([typeString isEqualToString:kNCSignalingMessageTypeOfferKey] ||
               [typeString isEqualToString:kNCSignalingMessageTypeAnswerKey]) {
        message = [[NCSessionDescriptionMessage alloc] initWithValues:values];
    } else {
        RTCLogError(@"Unexpected type: %@", typeString);
    }
    
    return message;
}

- (NSData *)JSONData {
    return nil;
}

- (NSDictionary *)messageDict {
    return nil;
}

- (NCSignalingMessageType)messageType {
    return kNCSignalingMessageTypeUknown;
}

+ (NSString *)getMessageSid {
    NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970];
    return [[NSNumber numberWithDouble: timeStamp] stringValue];
}

@end

@implementation NCICECandidateMessage

@synthesize candidate = _candidate;

- (instancetype)initWithValues:(NSDictionary *)values {
    RTCIceCandidate *candidate = [RTCIceCandidate candidateFromJSONDictionary:[[values objectForKey:kNCSignalingMessagePayloadKey] objectForKey:kNCSignalingMessageTypeCandidateKey]];
    return [self initWithCandidate:candidate
                              from:[values objectForKey:kNCSignalingMessageFromKey]
                                to:[values objectForKey:kNCSignalingMessageToKey]
                               sid:[values objectForKey:kNCSignalingMessageSidKey]
                          roomType:[values objectForKey:kNCSignalingMessageRoomTypeKey]];
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
{
    NSDictionary *payload = [[NSDictionary alloc] init];
    self = [super initWithFrom:from
                            to:to
                           sid:sid
                          type:kNCSignalingMessageTypeCandidateKey
                       payload:payload
                      roomType:roomType];
    
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
    RTCSessionDescription *description = [RTCSessionDescription descriptionFromJSONDictionary:[values objectForKey:kNCSignalingMessagePayloadKey]];
    NSString *nick = [[values objectForKey:kNCSignalingMessagePayloadKey] objectForKey:kNCSignalingMessageNickKey];
    return [self initWithSessionDescription:description
                                       from:[values objectForKey:kNCSignalingMessageFromKey]
                                         to:[values objectForKey:kNCSignalingMessageToKey]
                                        sid:[values objectForKey:kNCSignalingMessageSidKey]
                                   roomType:[values objectForKey:kNCSignalingMessageRoomTypeKey]
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
                                      nick:(NSString *)nick
{
    RTCSdpType sdpType = sessionDescription.type;
    NSString *type = nil;
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
                      roomType:roomType];
    
    if (!self) {
        return nil;
    }
    
    _sessionDescription = sessionDescription;
    _nick = nick;
    
    return self;
}

@end
