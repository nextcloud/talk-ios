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

@end
