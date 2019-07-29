//
//  RoomInfoTableViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 02.07.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NCRoom.h"
#import "NCChatViewController.h"

@interface RoomInfoTableViewController : UITableViewController

- (instancetype)initForRoom:(NCRoom *)room;
- (instancetype)initForRoom:(NCRoom *)room fromChatViewController:(NCChatViewController *)chatViewController;

@end
