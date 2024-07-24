/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

@interface RoomsTableViewController : UITableViewController

@property (nonatomic) NSString *selectedRoomToken;

- (void)setSelectedRoomToken:(NSString *)selectedRoomToken;
- (void)highlightSelectedRoom;
- (void)removeRoomSelection;

@end
