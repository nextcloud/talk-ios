//
//  RoomCreation2TableViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 19.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString * const NCRoomCreatedNotification;

@interface RoomCreation2TableViewController : UITableViewController

- (instancetype)initForGroupRoomWithParticipants:(NSMutableArray *)participants;
- (instancetype)initForPublicRoom;

@end
