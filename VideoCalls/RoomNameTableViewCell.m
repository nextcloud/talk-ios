//
//  RoomNameTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 19.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "RoomNameTableViewCell.h"

NSString *const kRoomNameCellIdentifier     = @"RoomNameCellIdentifier";
NSString *const kRoomNameTableCellNibName   = @"RoomNameTableViewCell";

@implementation RoomNameTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
