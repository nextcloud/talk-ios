//
//  AddParticipantsTableViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.01.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "NCRoom.h"

@class AddParticipantsTableViewController;
@protocol AddParticipantsTableViewControllerDelegate <NSObject>

- (void)addParticipantsTableViewControllerDidFinish:(AddParticipantsTableViewController *)viewController;

@end

@interface AddParticipantsTableViewController : UITableViewController

@property (nonatomic, weak) id<AddParticipantsTableViewControllerDelegate> delegate;

- (instancetype)initForRoom:(NCRoom *)room;

@end
