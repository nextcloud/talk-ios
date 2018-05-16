//
//  NCChatViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "SLKTextViewController.h"

#import "NCRoom.h"

@interface NCChatViewController : SLKTextViewController

- (instancetype)initForRoom:(NCRoom *)room;

@end
