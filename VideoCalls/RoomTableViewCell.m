//
//  RoomTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 19.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "RoomTableViewCell.h"
#import "UIImageView+AFNetworking.h"

NSString *const kRoomCellIdentifier = @"RoomCellIdentifier";

@implementation RoomTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.roomImage.layer.cornerRadius = 24.0;
    self.roomImage.layer.masksToBounds = YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.roomImage cancelImageDownloadTask];
    
    self.roomImage.image = nil;
    
    for (UIView *subview in [self.unreadMessagesView subviews]) {
        [subview removeFromSuperview];
    }
}

@end
