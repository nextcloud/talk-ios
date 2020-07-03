//
//  NCDatabaseManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 08.05.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "NCDatabaseManager.h"

#import "NCChatController.h"
#import "NCChatMessage.h"
#import "NCRoom.h"

NSString *const kTalkDatabaseFolder         = @"Library/Application Support/Talk";
NSString *const kTalkDatabaseFileName       = @"talk.realm";
uint64_t const kTalkDatabaseSchemaVersion   = 2;

@implementation TalkAccount
+ (NSString *)primaryKey {
    return @"accountId";
}
@end

@implementation ServerCapabilities
+ (NSString *)primaryKey {
    return @"accountId";
}
@end

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
        NSString *path = [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.com.nextcloud.Talk"] URLByAppendingPathComponent:kTalkDatabaseFolder] path];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionNone} ofItemAtPath:path error:nil];
        
        // Set Realm configuration
        RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
        NSURL *databaseURL = [[NSURL fileURLWithPath:path] URLByAppendingPathComponent:kTalkDatabaseFileName];
        configuration.fileURL = databaseURL;
        configuration.schemaVersion = kTalkDatabaseSchemaVersion;
        [RLMRealmConfiguration setDefaultConfiguration:configuration];
        
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
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *removeAccount = [TalkAccount objectsWithPredicate:query].firstObject;
    ServerCapabilities *serverCapabilities = [ServerCapabilities objectsWithPredicate:query].firstObject;
    [realm beginWriteTransaction];
    [realm deleteObject:removeAccount];
    if (serverCapabilities) {
        [realm deleteObject:serverCapabilities];
    }
    [realm deleteObjects:[NCRoom objectsWithPredicate:query]];
    [realm deleteObjects:[NCChatMessage objectsWithPredicate:query]];
    [realm deleteObjects:[NCChatBlock objectsWithPredicate:query]];
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
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm beginWriteTransaction];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"accountId = %@", accountId];
    TalkAccount *account = [TalkAccount objectsWithPredicate:query].firstObject;
    account.unreadBadgeNumber = 0;
    account.unreadNotification = NO;
    [realm commitWriteTransaction];
}

- (BOOL)shouldShowUnreadNotificationForInactiveAccounts
{
    TalkAccount *accountToBeNotified = [TalkAccount objectsWhere:(@"active = false AND unreadNotification = true")].firstObject;
    if (accountToBeNotified) {
        return YES;
    }
    return NO;
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
    NSDictionary *version = [serverCapabilities objectForKey:@"version"];
    NSDictionary *themingCaps = [serverCaps objectForKey:@"theming"];
    NSDictionary *talkCaps = [serverCaps objectForKey:@"spreed"];
    
    ServerCapabilities *capabilities = [[ServerCapabilities alloc] init];
    capabilities.accountId = accountId;
    capabilities.name = [themingCaps objectForKey:@"name"];
    capabilities.slogan = [themingCaps objectForKey:@"slogan"];
    capabilities.url = [themingCaps objectForKey:@"url"];
    capabilities.logo = [themingCaps objectForKey:@"logo"];
    capabilities.color = [themingCaps objectForKey:@"color"];
    capabilities.colorElement = [themingCaps objectForKey:@"color-element"];
    capabilities.colorText = [themingCaps objectForKey:@"color-text"];
    capabilities.background = [themingCaps objectForKey:@"background"];
    capabilities.backgroundDefault = [[themingCaps objectForKey:@"background-default"] boolValue];
    capabilities.backgroundPlain = [[themingCaps objectForKey:@"background-plain"] boolValue];
    capabilities.version = [version objectForKey:@"string"];
    capabilities.versionMajor = [[version objectForKey:@"major"] integerValue];
    capabilities.versionMinor = [[version objectForKey:@"minor"] integerValue];
    capabilities.versionMicro = [[version objectForKey:@"micro"] integerValue];
    capabilities.edition = [version objectForKey:@"edition"];
    capabilities.extendedSupport = [[version objectForKey:@"extendedSupport"] boolValue];
    capabilities.talkCapabilities = [talkCaps objectForKey:@"features"];
    capabilities.chatMaxLength = [[[[talkCaps objectForKey:@"config"] objectForKey:@"chat"] objectForKey:@"max-length"] integerValue];
    if ([[[[talkCaps objectForKey:@"config"] objectForKey:@"conversations"] allKeys] containsObject:@"can-create"]) {
        capabilities.canCreate = [[[[talkCaps objectForKey:@"config"] objectForKey:@"conversations"] objectForKey:@"can-create"] boolValue];
    } else {
        capabilities.canCreate = YES;
    }
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [realm addOrUpdateObject:capabilities];
    }];
}

@end
