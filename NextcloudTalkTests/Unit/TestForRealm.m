//
//  TestForRealm.m
//  NextcloudTalkTests
//
//  Created by Marcel Müller on 25.01.24.
//

#import "TestForRealm.h"

@implementation TestForRealm

- (RLMRealm *)setupRealm
{
    // Setup in memory database
    /*let config = RLMRealmConfiguration()
    // Use a UUID to create a new/empty database for each test
    config.inMemoryIdentifier = UUID().uuidString

    RLMRealmConfiguration.setDefault(config)

    realm = RLMRealm.default()
     */
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.inMemoryIdentifier = [[[NSUUID alloc] init] UUIDString];
    configuration.schemaVersion = 99;
    //configuration.objectClasses = @[TalkAccount.class, NCRoom.class, ServerCapabilities.class];
    configuration.migrationBlock = ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
        // At the very minimum we need to update the version with an empty block to indicate that the schema has been upgraded (automatically) by Realm
    };
    [RLMRealmConfiguration setDefaultConfiguration:configuration];

    return [RLMRealm defaultRealm];
}

@end
