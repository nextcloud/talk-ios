//
//  NCAPISessionManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 30.11.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"

@interface NCAPISessionManager : AFHTTPSessionManager

@property (nonatomic, strong) NSString *userAgent;

@end
