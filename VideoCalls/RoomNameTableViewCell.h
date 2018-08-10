//
//  RoomNameTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 19.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const kRoomNameCellIdentifier;
extern NSString *const kRoomNameTableCellNibName;

@interface RoomNameTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UIImageView *roomImage;
@property (weak, nonatomic) IBOutlet UITextField *roomNameTextField;
@property (weak, nonatomic) IBOutlet UIImageView *favoriteImage;

@end
