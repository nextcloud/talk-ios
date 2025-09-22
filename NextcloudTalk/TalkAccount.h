/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@interface TalkAccount : RLMObject

@property NSString *accountId;
@property NSString *server;
@property NSString *user;
@property NSString *userId;
@property NSString *userDisplayName;
@property NSString *userDisplayNameScope;
@property NSString *phone;
@property NSString *phoneScope;
@property NSString *email;
@property NSString *emailScope;
@property NSString *address;
@property NSString *addressScope;
@property NSString *website;
@property NSString *websiteScope;
@property NSString *twitter;
@property NSString *twitterScope;
@property NSInteger lastPushSubscription;
@property NSString *deviceIdentifier;
@property NSString *deviceSignature;
@property NSString *userPublicKey;
@property NSInteger unreadBadgeNumber;
@property BOOL unreadNotification;
@property NSInteger lastContactSync;
@property NSString *avatarScope;
@property BOOL hasCustomAvatar;
@property BOOL hasContactSyncEnabled;
@property BOOL active;
@property NSString * _Nullable lastReceivedConfigurationHash;
@property NSString *lastReceivedModifiedSince;
@property NSInteger lastNotificationId;
@property NSString *lastNotificationETag;
@property NSInteger pendingFederationInvitations;
@property NSString *frequentlyUsedEmojisJSONString;
@property RLMArray<RLMString> *groupIds;
@property RLMArray<RLMString> *teamIds;
@property BOOL hasThreads;
@property NSInteger threadsLastCheckTimestamp;

@end

NS_ASSUME_NONNULL_END
