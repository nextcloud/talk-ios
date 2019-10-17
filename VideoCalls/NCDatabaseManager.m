//
//  NCDatabaseManager.m
//  VideoCalls
//
//  Created by Ivan Sein on 08.05.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "NCDatabaseManager.h"

#define k_TalkDatabaseFolder    @"Library/Application Support/Talk"
#define k_TalkDatabaseFileName  @"talk.realm"

@implementation TalkAccount
+ (NSString *)primaryKey {
    return @"account";
}
@end

@implementation ServerCapabilities
+ (NSString *)primaryKey {
    return @"account";
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
        NSString *path = [[[[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.com.nextcloud.Talk"] URLByAppendingPathComponent:k_TalkDatabaseFolder] path];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey:NSFileProtectionNone} ofItemAtPath:path error:nil];
        
        // Set Realm configuration
        RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
        NSURL *databaseURL = [[NSURL fileURLWithPath:path] URLByAppendingPathComponent:k_TalkDatabaseFileName];
        configuration.fileURL = databaseURL;
        [RLMRealmConfiguration setDefaultConfiguration:configuration];
        
#ifdef DEBUG
        // Copy Talk DB to Documents directory
        NSString *dbCopyPath = [NSString stringWithFormat:@"%@/%@", NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0], k_TalkDatabaseFileName];
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
    return [TalkAccount objectsWhere:(@"active = true")].firstObject;
}

- (void)createAccountForUser:(NSString *)user inServer:(NSString *)server
{
    TalkAccount *account =  [[TalkAccount alloc] init];
    account.account = [NSString stringWithFormat:@"%@@%@", user, server];
    account.server = server;
    account.user = user;
    account.active = YES;
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [realm addObject:account];
    }];
}

- (void)removeAccount:(NSString *)account
{
    RLMRealm *realm = [RLMRealm defaultRealm];
    NSPredicate *query = [NSPredicate predicateWithFormat:@"account = %@", account];
    TalkAccount *removeAccount = [TalkAccount objectsWithPredicate:query].firstObject;
    [realm beginWriteTransaction];
    [realm deleteObject:removeAccount];
    [realm commitWriteTransaction];
}

#pragma mark - Server capabilities

- (ServerCapabilities *)serverCapabilitiesForAccount:(NSString *)account
{
    NSPredicate *query = [NSPredicate predicateWithFormat:@"account = %@", account];
    return [ServerCapabilities objectsWithPredicate:query].firstObject;
}

- (void)setServerCapabilities:(NSDictionary *)serverCapabilities forAccount:(NSString *)account
{
    NSDictionary *serverCaps = [serverCapabilities objectForKey:@"capabilities"];
    NSDictionary *version = [serverCapabilities objectForKey:@"version"];
    NSDictionary *themingCaps = [serverCaps objectForKey:@"theming"];
    NSDictionary *talkCaps = [serverCaps objectForKey:@"spreed"];
    
    ServerCapabilities *capabilities = [[ServerCapabilities alloc] init];
    capabilities.account = account;
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
    
    RLMRealm *realm = [RLMRealm defaultRealm];
    [realm transactionWithBlock:^{
        [realm addOrUpdateObject:capabilities];
    }];
}

@end
