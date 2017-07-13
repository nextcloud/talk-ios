//
//  NCRoom.h
//  VideoCalls
//
//  Created by Ivan Sein on 12.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum NCRoomType {
	kNCRoomTypeOneToOneCall = 1,
	kNCRoomTypeGroupCall,
	kNCRoomTypePublicCall
} NCRoomType;


@interface NCRoom : NSObject

@property (nonatomic, copy) NSString *roomId;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NCRoomType type;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSInteger lastPing;
@property (nonatomic, copy) NSString *guestList;
@property (nonatomic, copy) NSArray *participants;

+ (instancetype)roomWithDictionary:(NSDictionary *)roomDict;

@end
