/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "NCDatabaseManager.h"

#import "ABContact.h"
#import "NCAppBranding.h"
#import "NCChatBlock.h"
#import "NCChatMessage.h"
#import "NCContact.h"
#import "NCRoom.h"

#import "NextcloudTalk-Swift.h"

NSString *const kTalkDatabaseFolder                 = @"Library/Application Support/Talk";
NSString *const kTalkDatabaseFileName               = @"talk.realm";
uint64_t const kTalkDatabaseSchemaVersion           = 42;

NSString * const kCapabilitySystemMessages          = @"system-messages";
NSString * const kCapabilityNotificationLevels      = @"notification-levels";
NSString * const kCapabilityInviteGroupsAndMails    = @"invite-groups-and-mails";
NSString * const kCapabilityLockedOneToOneRooms     = @"locked-one-to-one-rooms";
NSString * const kCapabilityWebinaryLobby           = @"webinary-lobby";
NSString * const kCapabilityChatReadMarker          = @"chat-read-marker";
NSString * const kCapabilityStartCallFlag           = @"start-call-flag";
NSString * const kCapabilityCirclesSupport          = @"circles-support";
NSString * const kCapabilityChatReferenceId         = @"chat-reference-id";
NSString * const kCapabilityPhonebookSearch         = @"phonebook-search";
NSString * const kCapabilityChatReadStatus          = @"chat-read-status";
NSString * const kCapabilityReadOnlyRooms           = @"read-only-rooms";
NSString * const kCapabilityListableRooms           = @"listable-rooms";
NSString * const kCapabilityDeleteMessages          = @"delete-messages";
NSString * const kCapabilityCallFlags               = @"conversation-call-flags";
NSString * const kCapabilityRoomDescription         = @"room-description";
NSString * const kCapabilityTempUserAvatarAPI       = @"temp-user-avatar-api";
NSString * const kCapabilityLocationSharing         = @"geo-location-sharing";
NSString * const kCapabilityConversationV4          = @"conversation-v4";
NSString * const kCapabilitySIPSupport              = @"sip-support";
NSString * const kCapabilitySIPSupportNoPIN         = @"sip-support-nopin";
NSString * const kCapabilityVoiceMessage            = @"voice-message-sharing";
NSString * const kCapabilitySignalingV3             = @"signaling-v3";
NSString * const kCapabilityClearHistory            = @"clear-history";
NSString * const kCapabilityDirectMentionFlag       = @"direct-mention-flag";
NSString * const kCapabilityNotificationCalls       = @"notification-calls";
NSString * const kCapabilityConversationPermissions = @"conversation-permissions";
NSString * const kCapabilityChatUnread              = @"chat-unread";
NSString * const kCapabilityReactions               = @"reactions";
NSString * const kCapabilityRichObjectListMedia     = @"rich-object-list-media";
NSString * const kCapabilityRichObjectDelete        = @"rich-object-delete";
NSString * const kCapabilityUnifiedSearch           = @"unified-search";
NSString * const kCapabilityChatPermission          = @"chat-permission";
NSString * const kCapabilityMessageExpiration       = @"message-expiration";
NSString * const kCapabilitySilentSend              = @"silent-send";
NSString * const kCapabilitySilentCall              = @"silent-call";
NSString * const kCapabilitySendCallNotification    = @"send-call-notification";
NSString * const kCapabilityTalkPolls               = @"talk-polls";

NSString * const kMinimumRequiredTalkCapability     = kCapabilitySystemMessages; // Talk 4.0 is the minimum required version

@implementation NCDatabaseManager

+ (NCDatabaseManager *)sharedInstance
{
    static dispatch_once_t once;
    static NCDatabaseManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        // Create Talk database directory
        NSString *path = [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupIdentifier] URLByAppendingPathComponent:kTalkDatabaseFolder] path];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionNone} ofItemAtPath:path error:nil];
        
        // Set Realm configuration
        RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
        NSURL *databaseURL = [[NSURL fileURLWithPath:path] URLByAppendingPathComponent:kTalkDatabaseFileName];
        configuration.fileURL = databaseURL;
        configuration.schemaVersion = kTalkDatabaseSchemaVersion;
        configuration.migrationBlock = ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
            // At the very minimum we need to update the version with an empty block to indicate that the schema has been upgraded (automatically) by Realm
        };
        
        // Tell Realm to use this new configuration object for the default Realm
        [RLMRealmConfiguration setDefaultConfiguration:configuration];

        // Now that we've told Realm how to handle the schema change, opening the file
        // will automatically perform the migration
        [RLMRealm defaultRealm];
        
#ifdef DEBUG
        // Copy Talk DB to Documents directory
        NSString *dbCopyPath = [NSString stringWithFormat:@"%@/%@", NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0], kTalkDatabaseFileName];
        NSURL *dbCopyURL = [NSURL fileURLWithPath:dbCopyPath];
        [[NSFileManager defaultManager] removeItemAtURL:dbCopyURL error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:databaseURL toURL:dbCopyURL error:nil];
#endif
    }
    
    return self;
}

#pragma mark - Talk accounts

- (NSInteger)numberOfAccounts
{
    return [TalkAccount allObjects].count;
}

- (TalkAccount *)activeAccount
{
    TalkAccount *managedActiveAccount = [TalkAccount objectsWhere:(@"active = true")].firstObject;
    if (managedActiveAccount) {
        return [[TalkAccount alloc] initWithValue:managedActiveAccount];
    }
    return nil;
}

- (NSArray *)allAccounts
{
    NSMutableArray *allAccounts = [NSMutableArray new];
    for (TalkAccount *managedAccount in [TalkAccount allObjects]) {
        TalkAccount *account = [[TalkAccount alloc] initWithValue:managedAccount];
        [allAccounts addObject:account];
    }
    return allAccounts;
}

- (NSArray *)inactiveAccounts
{
    NSMutableArray *inactiveAccounts = [NSMutableArray new];
    for (TalkAccount *managedInactiveAccount in [TalkAccount objectsWhere:(@"active = false")]) {
        TalkAccount *inactiveAccount = [[TalkAccount alloc] initWithValue:managedInactiveAccount];
        [inactiveAccounts addObject:inactiveAccount];
    }
    return inactiveAccounts;
}

- (TalkAccount *)talkAccountForAccountId:(NSString *)accountId
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
    if (managedAccount) {
        return [[TalkAccount alloc] initWithValue:managedAccount];
    }
    return nil;
}

- (TalkAccount *)talkAccountForUserId:(NSString *)userId inServer:(NSString *)server
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"userId = %@ AND server = %@", userId, server];
    TalkAccount *managedAccount = [TalkAccount objectsWithPredicate:query].firstObject;
    if (managedAccount) {
        return [[TalkAccount alloc] initWithValue:managedAccount];
    }
    return nil;
}

- (void)setActiveAccountWithAccountId:(NSString *)accountId
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    for (TalkAccount *account in [TalkAccount allObjects]) {
        account.active = NO;
    }
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *activeAccount = [TalkAccount objectsWithPredicate:query].firstObject;
    activeAccount.active = YES;
    [realm commitWriteTransaction];
}

- (NSString *)accountIdForUser:(NSString *)user inServer:(NSString *)server
{
    return [NSString stringWithFormat:@"%@@%@", user, server];
}

- (void)createAccountForUser:(NSString *)user inServer:(NSString *)server
{
    TalkAccount *account =  [[TalkAccount alloc] init];
    NSString *accountId = [self accountIdForUser:user inServer:server];
    account.accountId = accountId;
    account.server = server;
    account.user = user;
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [realm addObject:account];
    }];
}

- (void)removeAccountWithAccountId:(NSString *)accountId
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    BOOL isLastAccount = [self numberOfAccounts] == 1;
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *removeAccount = [TalkAccount objectsWithPredicate:query].firstObject;
    if (removeAccount) {
        [realm deleteObject:removeAccount];
    }
    ServerCapabilities *serverCapabilities = [ServerCapabilities objectsWithPredicate:query].firstObject;
    if (serverCapabilities) {
        [realm deleteObject:serverCapabilities];
    }
    [realm deleteObjects:[NCRoom objectsWithPredicate:query]];
    [realm deleteObjects:[NCChatMessage objectsWithPredicate:query]];
    [realm deleteObjects:[NCChatBlock objectsWithPredicate:query]];
    [realm deleteObjects:[NCContact objectsWithPredicate:query]];
    if (isLastAccount) {
        [realm deleteObjects:[ABContact allObjects]];
    }
    [realm commitWriteTransaction];
}

- (void)increaseUnreadBadgeNumberForAccountId:(NSString *)accountId
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *account = [TalkAccount objectsWithPredicate:query].firstObject;
    account.unreadBadgeNumber += 1;
    account.unreadNotification = YES;
    [realm commitWriteTransaction];
}

- (void)decreaseUnreadBadgeNumberForAccountId:(NSString *)accountId
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *account = [TalkAccount objectsWithPredicate:query].firstObject;
    account.unreadBadgeNumber = (account.unreadBadgeNumber > 0) ? account.unreadBadgeNumber - 1 : 0;
    account.unreadNotification = (account.unreadBadgeNumber > 0) ? account.unreadNotification : NO;
    [realm commitWriteTransaction];
}

- (void)resetUnreadBadgeNumberForAccountId:(NSString *)accountId
{
    BGTaskHelper *bgTask = [BGTaskHelper startBackgroundTaskWithName:@"resetUnreadBadgeNumberForAccountId" expirationHandler:nil];
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *account = [TalkAccount objectsWithPredicate:query].firstObject;
    account.unreadBadgeNumber = 0;
    account.unreadNotification = NO;
    [realm commitWriteTransaction];
    [bgTask stopBackgroundTask];
}

- (NSInteger)numberOfInactiveAccountsWithUnreadNotifications
{
    return [TalkAccount objectsWhere:(@"active = false AND unreadNotification = true")].count;
}

- (NSInteger)numberOfUnreadNotifications
{
    NSInteger unreadNotifications = 0;
    for (TalkAccount *account in [TalkAccount allObjects]) {
        unreadNotifications += account.unreadBadgeNumber;
    }
    return unreadNotifications;
}

- (void)removeUnreadNotificationForInactiveAccounts
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    for (TalkAccount *account in [TalkAccount allObjects]) {
        account.unreadNotification = NO;
    }
    [realm commitWriteTransaction];
}

- (void)updateTalkConfigurationHashForAccountId:(NSString *)accountId withHash:(nonnull NSString *)hash
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *account = [TalkAccount objectsWithPredicate:query].firstObject;
    account.lastReceivedConfigurationHash = hash;
    [realm commitWriteTransaction];
}

#pragma mark - Server capabilities

- (ServerCapabilities *)serverCapabilitiesForAccountId:(NSString *)accountId
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    ServerCapabilities *managedServerCapabilities = [ServerCapabilities objectsWithPredicate:query].firstObject;
    if (managedServerCapabilities) {
        return [[ServerCapabilities alloc] initWithValue:managedServerCapabilities];
    }
    return nil;
}

- (void)setServerCapabilities:(NSDictionary *)serverCapabilities forAccountId:(NSString *)accountId
{
    NSDictionary *serverCaps = [serverCapabilities objectForKey:@"capabilities"];
    NSDictionary *coreCaps = [serverCaps objectForKey:@"core"];
    NSDictionary *version = [serverCapabilities objectForKey:@"version"];
    NSDictionary *themingCaps = [serverCaps objectForKey:@"theming"];
    NSDictionary *talkCaps = [serverCaps objectForKey:@"spreed"];
    NSDictionary *userStatusCaps = [serverCaps objectForKey:@"user_status"];
    NSDictionary *provisioningAPICaps = [serverCaps objectForKey:@"provisioning_api"];
    NSDictionary *guestsCaps = [serverCaps objectForKey:@"guests"];
    NSDictionary *notificationsCaps = [serverCaps objectForKey:@"notifications"];
    
    ServerCapabilities *capabilities = [[ServerCapabilities alloc] init];
    capabilities.accountId = accountId;
    capabilities.name = [themingCaps objectForKey:@"name"];
    capabilities.slogan = [themingCaps objectForKey:@"slogan"];
    capabilities.url = [themingCaps objectForKey:@"url"];
    capabilities.logo = [themingCaps objectForKey:@"logo"];
    capabilities.color = [themingCaps objectForKey:@"color"];
    capabilities.colorElement = [themingCaps objectForKey:@"color-element"];
    capabilities.colorElementBright = [themingCaps objectForKey:@"color-element-bright"];
    capabilities.colorElementDark = [themingCaps objectForKey:@"color-element-dark"];
    capabilities.colorText = [themingCaps objectForKey:@"color-text"];
    capabilities.background = [themingCaps objectForKey:@"background"];
    capabilities.backgroundDefault = [[themingCaps objectForKey:@"background-default"] boolValue];
    capabilities.backgroundPlain = [[themingCaps objectForKey:@"background-plain"] boolValue];
    capabilities.version = [version objectForKey:@"string"];
    capabilities.versionMajor = [[version objectForKey:@"major"] integerValue];
    capabilities.versionMinor = [[version objectForKey:@"minor"] integerValue];
    capabilities.versionMicro = [[version objectForKey:@"micro"] integerValue];
    capabilities.edition = [version objectForKey:@"edition"];
    capabilities.userStatus = [[userStatusCaps objectForKey:@"enabled"] boolValue];
    capabilities.extendedSupport = [[version objectForKey:@"extendedSupport"] boolValue];
    capabilities.talkCapabilities = [talkCaps objectForKey:@"features"];
    capabilities.chatMaxLength = [[[[talkCaps objectForKey:@"config"] objectForKey:@"chat"] objectForKey:@"max-length"] integerValue];
    if ([[[[talkCaps objectForKey:@"config"] objectForKey:@"conversations"] allKeys] containsObject:@"can-create"]) {
        capabilities.canCreate = [[[[talkCaps objectForKey:@"config"] objectForKey:@"conversations"] objectForKey:@"can-create"] boolValue];
    } else {
        capabilities.canCreate = YES;
    }
    capabilities.attachmentsAllowed = [[[[talkCaps objectForKey:@"config"] objectForKey:@"attachments"] objectForKey:@"allowed"] boolValue];
    capabilities.attachmentsFolder = [[[talkCaps objectForKey:@"config"] objectForKey:@"attachments"] objectForKey:@"folder"];
    capabilities.readStatusPrivacy = [[[[talkCaps objectForKey:@"config"] objectForKey:@"chat"] objectForKey:@"read-privacy"] boolValue];
    capabilities.accountPropertyScopesVersion2 = [[provisioningAPICaps objectForKey:@"AccountPropertyScopesVersion"] integerValue] == 2;
    capabilities.accountPropertyScopesFederationEnabled = [[provisioningAPICaps objectForKey:@"AccountPropertyScopesFederationEnabled"] boolValue];
    if ([[[[talkCaps objectForKey:@"config"] objectForKey:@"call"] allKeys] containsObject:@"enabled"]) {
        capabilities.callEnabled = [[[[talkCaps objectForKey:@"config"] objectForKey:@"call"] objectForKey:@"enabled"] boolValue];
    } else {
        capabilities.callEnabled = YES;
    }
    capabilities.talkVersion = [talkCaps objectForKey:@"version"];
    capabilities.guestsAppEnabled = [[guestsCaps objectForKey:@"enabled"] boolValue];
    capabilities.referenceApiSupported = [[coreCaps objectForKey:@"reference-api"] boolValue];
    capabilities.notificationsAppEnabled = ([notificationsCaps objectForKey:@"ocs-endpoints"] != nil);
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [realm addOrUpdateObject:capabilities];
    }];
}

- (BOOL)serverHasTalkCapability:(NSString *)capability
{
    TalkAccount *activeAccount = [self activeAccount];
    return [self serverHasTalkCapability:capability forAccountId:activeAccount.accountId];
}

- (BOOL)serverHasTalkCapability:(NSString *)capability forAccountId:(NSString *)accountId
{
    ServerCapabilities *serverCapabilities  = [self serverCapabilitiesForAccountId:accountId];
    if (serverCapabilities) {
        NSArray *talkFeatures = [serverCapabilities.talkCapabilities valueForKey:@"self"];
        if ([talkFeatures containsObject:capability]) {
            return YES;
        }
    }
    return NO;
}

- (void)setExternalSignalingServerVersion:(NSString *)version forAccountId:(NSString *)accountId
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
        ServerCapabilities *managedServerCapabilities = [ServerCapabilities objectsWithPredicate:query].firstObject;
        
        if (managedServerCapabilities && managedServerCapabilities.externalSignalingServerVersion != version) {
            managedServerCapabilities.externalSignalingServerVersion = version;
        }
    }];
}

@end
