//
//  NCDatabaseManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 08.05.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@interface TalkAccount : RLMObject
@property NSString *account;
@property NSString *server;
@property NSString *user;
@property NSString *userId;
@property NSString *userDisplayName;
@property NSString *pushKitToken;
@property NSString *pushNotificationServer;
@property NSString *pushNotificationSubscribed;
@property NSString *pushNotificationPublicKey;
@property NSString *deviceIdentifier;
@property NSString *deviceSignature;
@property NSString *userPublicKey;
@end

@interface NCDatabaseManager : NSObject

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
