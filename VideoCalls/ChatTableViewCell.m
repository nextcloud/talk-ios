//
//  ChatTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 04.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "ChatTableViewCell.h"

@implementation ChatTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.messageId = -1;
}

@end
