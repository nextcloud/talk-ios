//
//  AddParticipantsTableViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.01.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "NCRoom.h"

@interface AddParticipantsTableViewController : UITableViewController

- (instancetype)initForRoom:(NCRoom *)room;

@end
