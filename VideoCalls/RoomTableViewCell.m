//
//  RoomTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 19.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "RoomTableViewCell.h"

NSString *const kRoomCellIdentifier = @"RoomCellIdentifier";

@implementation RoomTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.roomImage.layer.cornerRadius = 24.0;
    self.roomImage.layer.masksToBounds = YES;
    self.roomPasswordImage.contentMode = UIViewContentModeCenter;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.roomPasswordImage.image = nil;
    self.roomImage.image = nil;
    self.roomImage.backgroundColor = [UIColor clearColor];
    self.roomImage.contentMode = UIViewContentModeScaleToFill;
}

@end
