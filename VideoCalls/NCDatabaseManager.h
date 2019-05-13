//
//  NCDatabaseManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 08.05.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCDatabaseManager : NSObject

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
