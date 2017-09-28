//
//  RoomTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 19.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const kRoomCellIdentifier;

@interface RoomTableViewCell : UITableViewCell

@property(nonatomic, weak) IBOutlet UIImageView *roomImage;
@property(nonatomic, weak) IBOutlet UILabel *labelTitle;
@property(nonatomic, weak) IBOutlet UILabel *labelSubTitle;

@end
