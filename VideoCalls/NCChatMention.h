//
//  NCChatMention.h
//  VideoCalls
//
//  Created by Ivan Sein on 27.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NCChatMention : NSObject

@property (nonatomic, assign) NSRange range;
@property (nonatomic, strong) NSString *userId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) BOOL ownMention;

@end
