//
//  NCAPIController.h
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^GetRoomsCompletionBlock)(NSMutableArray *rooms, NSError *error, NSInteger errorCode);
typedef void (^GetContactsCompletionBlock)(NSMutableArray *contacts, NSError *error, NSInteger errorCode);

@interface NCAPIController : NSObject

+ (instancetype)sharedInstance;
- (void)setNCServer:(NSString *)serverUrl;
- (void)setAuthHeaderWithUser:(NSString *)user andToken:(NSString *)token;
- (void)getRoomsWithCompletionBlock:(GetRoomsCompletionBlock)block;
- (void)getContactsWithCompletionBlock:(GetContactsCompletionBlock)block;

@end
