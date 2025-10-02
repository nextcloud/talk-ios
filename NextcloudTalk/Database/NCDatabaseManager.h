/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

#import "TalkAccount.h"
#import "ServerCapabilities.h"
#import "FederatedCapabilities.h"

@class NCRoom;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kTalkDatabaseFolder;
extern NSString *const kTalkDatabaseFileName;
extern uint64_t const kTalkDatabaseSchemaVersion;

extern NSString * const kCapabilitySystemMessages;
extern NSString * const kCapabilityNotificationLevels;
extern NSString * const kCapabilityInviteGroupsAndMails;
extern NSString * const kCapabilityLockedOneToOneRooms;
extern NSString * const kCapabilityWebinaryLobby;
extern NSString * const kCapabilityChatReadMarker;
extern NSString * const kCapabilityStartCallFlag;
extern NSString * const kCapabilityCirclesSupport;
extern NSString * const kCapabilityChatReferenceId;
extern NSString * const kCapabilityPhonebookSearch;
extern NSString * const kCapabilityChatReadStatus;
extern NSString * const kCapabilityReadOnlyRooms;
extern NSString * const kCapabilityListableRooms;
extern NSString * const kCapabilityDeleteMessages;
extern NSString * const kCapabilityCallFlags;
extern NSString * const kCapabilityRoomDescription;
extern NSString * const kCapabilityTempUserAvatarAPI;
extern NSString * const kCapabilityLocationSharing;
extern NSString * const kCapabilityConversationV4;
extern NSString * const kCapabilitySIPSupport;
extern NSString * const kCapabilitySIPSupportNoPIN;
extern NSString * const kCapabilityVoiceMessage;
extern NSString * const kCapabilitySignalingV3;
extern NSString * const kCapabilityClearHistory;
extern NSString * const kCapabilityDirectMentionFlag;
extern NSString * const kCapabilityNotificationCalls;
extern NSString * const kCapabilityConversationPermissions;
extern NSString * const kCapabilityChatUnread;
extern NSString * const kCapabilityReactions;
extern NSString * const kCapabilityRichObjectListMedia;
extern NSString * const kCapabilityRichObjectDelete;
extern NSString * const kCapabilityUnifiedSearch;
extern NSString * const kCapabilityChatPermission;
extern NSString * const kCapabilityMessageExpiration;
extern NSString * const kCapabilitySilentSend;
extern NSString * const kCapabilitySilentCall;
extern NSString * const kCapabilitySendCallNotification NS_SWIFT_NAME(kCapabilitySendCallNotification);
extern NSString * const kCapabilityTalkPolls;
extern NSString * const kCapabilityRaiseHand;
extern NSString * const kCapabilityRecordingV1;
extern NSString * const kCapabilitySingleConvStatus;
extern NSString * const kCapabilityChatKeepNotifications;
extern NSString * const kCapabilityConversationAvatars;
extern NSString * const kCapabilityTypingIndicators;
extern NSString * const kCapabilityPublishingPermissions;
extern NSString * const kCapabilityRemindMeLater;
extern NSString * const kCapabilityMarkdownMessages;
extern NSString * const kCapabilityNoteToSelf;
extern NSString * const kCapabilityMediaCaption;
extern NSString * const kCapabilityEditMessages;
extern NSString * const kCapabilityDeleteMessagesUnlimited;
extern NSString * const kCapabilityFederationV1;
extern NSString * const kCapabilityFederationV2;
extern NSString * const kCapabilityChatReadLast;
extern NSString * const kCapabilityBanV1;
extern NSString * const kCapabilityMentionPermissions;
extern NSString * const kCapabilityEditMessagesNoteToSelf;
extern NSString * const kCapabilityChatSummary;
extern NSString * const kCapabilityArchivedConversationsV2;
extern NSString * const kCapabilityCallNotificationState;
extern NSString * const kCapabilityCallForceMute;
extern NSString * const kCapabilityTalkPollsDrafts;
extern NSString * const kCapabilityEditDraftPoll;
extern NSString * const kCapabilityScheduleMeeting;
extern NSString * const kCapabilityConversationCreationAll;
extern NSString * const kCapabilityImportantConversations;
extern NSString * const kCapabilitySensitiveConversations;
extern NSString * const kCapabilityThreads;

extern NSString * const kNotificationsCapabilityExists;
extern NSString * const kNotificationsCapabilityTestPush;

extern NSString * const kMinimumRequiredTalkCapability;

extern NSString * const NCDatabaseManagerPendingFederationInvitationsDidChange;
extern NSString * const NCDatabaseManagerRoomCapabilitiesChangedNotification;

@interface NCTranslation : NSObject
@property (nonatomic, copy) NSString *from;
@property (nonatomic, copy) NSString *fromLabel;
@property (nonatomic, copy) NSString *to;
@property (nonatomic, copy) NSString *toLabel;
@end

@interface NCDatabaseManager : NSObject

+ (instancetype)sharedInstance;

- (NSInteger)numberOfAccounts;
- (TalkAccount *)activeAccount;
- (NSArray<TalkAccount *> *)allAccounts;
- (NSArray<TalkAccount *> *)inactiveAccounts;
- (TalkAccount * _Nullable)talkAccountForAccountId:(NSString *)accountId;
- (TalkAccount *)talkAccountForUserId:(NSString *)userId inServer:(NSString *)server;
- (void)setActiveAccountWithAccountId:(NSString *)accountId;
- (NSString *)accountIdForUser:(NSString *)user inServer:(NSString *)server;
- (void)createAccountForUser:(NSString *)user inServer:(NSString *)server;
- (void)removeAccountWithAccountId:(NSString *)accountId;
- (void)removeStoredMessagesForAccountId:(NSString *)accountId;
- (void)increaseUnreadBadgeNumberForAccountId:(NSString *)accountId;
- (void)decreaseUnreadBadgeNumberForAccountId:(NSString *)accountId;
- (void)resetUnreadBadgeNumberForAccountId:(NSString *)accountId;
- (NSInteger)numberOfUnreadNotifications;
- (NSInteger)numberOfInactiveAccountsWithUnreadNotifications;
- (void)removeUnreadNotificationForInactiveAccounts;
- (void)updateTalkConfigurationHashForAccountId:(NSString *)accountId withHash:(NSString *)hash;
- (void)updateLastModifiedSinceForAccountId:(NSString *)accountId with:(nonnull NSString *)modifiedSince;
- (void)updateHasThreadsForAccountId:(NSString *)accountId with:(BOOL)hasThreads;
- (void)updateThreadsLastCheckTimestampForAccountId:(NSString *)accountId with:(NSInteger)lastCheckTimestamp;

// Rooms
- (NCRoom * _Nullable)roomWithToken:(NSString *)token forAccountId:(NSString *)accountId;
- (NCRoom * _Nullable)roomWithInternalId:(NSString *)internalId;

// FederatedCapabilities
- (FederatedCapabilities * __nullable)federatedCapabilitiesForAccountId:(NSString *)accountId remoteServer:(NSString *)remoteServer roomToken:(NSString *)roomToken;
- (void)setFederatedCapabilities:(NSDictionary *)federatedCapabilitiesDict forAccountId:(NSString *)accountId remoteServer:(NSString *)remoteServer roomToken:(NSString *)roomToken withProxyHash:(NSString *)proxyHash;

// RoomCapabilities
- (BOOL)roomHasTalkCapability:(NSString *)capability forRoom:(NCRoom *)room;
- (TalkCapabilities * __nullable)roomTalkCapabilitiesForRoom:(NCRoom *)room;

// ServerCapabilities
- (ServerCapabilities * __nullable)serverCapabilities;
- (ServerCapabilities * __nullable)serverCapabilitiesForAccountId:(NSString *)accountId;
- (void)setServerCapabilities:(NSDictionary *)serverCapabilities forAccountId:(NSString *)accountId;
- (BOOL)serverHasTalkCapability:(NSString *)capability;
- (BOOL)serverHasTalkCapability:(NSString *)capability forAccountId:(NSString *)accountId;
- (BOOL)serverHasNotificationsCapability:(NSString *)capability forAccountId:(NSString *)accountId;
- (BOOL)serverCanInviteFederatedUsersforAccountId:(NSString *)accountId;
- (void)setExternalSignalingServerVersion:(NSString *)version forAccountId:(NSString *)accountId;

- (BOOL)hasAvailableTranslationsForAccountId:(NSString *)accountId;
- (BOOL)hasTranslationProvidersForAccountId:(NSString *)accountId;
- (NSArray<NCTranslation *> *)availableTranslationsForAccountId:(NSString *)accountId;
- (NSArray *)translationsFromTranslationsArray:(NSArray *)translations;

// Federation invitations
- (void)increasePendingFederationInvitationForAccountId:(NSString *)accountId;
- (void)decreasePendingFederationInvitationForAccountId:(NSString *)accountId;
- (void)setPendingFederationInvitationForAccountId:(NSString *)accountId with:(NSInteger)numberOfPendingInvitations;

@end

NS_ASSUME_NONNULL_END
