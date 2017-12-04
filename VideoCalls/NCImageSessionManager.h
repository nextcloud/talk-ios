//
//  NCImageSessionManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 04.12.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"

@interface NCImageSessionManager : AFHTTPSessionManager

@property (nonatomic, strong) NSString *userAgent;

+ (instancetype)sharedInstance;

@end
