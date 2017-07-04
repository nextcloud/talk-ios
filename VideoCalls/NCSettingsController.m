//
//  NCSettingsController.m
//  VideoCalls
//
//  Created by Ivan Sein on 26.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "NCSettingsController.h"

@implementation NCSettingsController

NSString * const kNCServerKey   = @"ncServer";
NSString * const kNCUserKey     = @"ncUser";
NSString * const kNCTokenKey    = @"ncToken";

+ (NCSettingsController *)sharedInstance
{
    static dispatch_once_t once;
    static NCSettingsController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        [self readValuesFromKeyChain];
    }
    return self;
}

- (void)readValuesFromKeyChain
{
    _ncServer = [UICKeyChainStore stringForKey:kNCServerKey];
    _ncUser = [UICKeyChainStore stringForKey:kNCUserKey];
    _ncToken = [UICKeyChainStore stringForKey:kNCTokenKey];
}

@end
