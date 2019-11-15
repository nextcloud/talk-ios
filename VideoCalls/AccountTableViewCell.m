//
//  AccountTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 30.10.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "AccountTableViewCell.h"

NSString *const kAccountCellIdentifier          = @"AccountCellIdentifier";
NSString *const kAccountTableViewCellNibName    = @"AccountTableViewCell";

@implementation AccountTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.accountImageView.layer.cornerRadius = 15.0;
    self.accountImageView.layer.masksToBounds = YES;
    self.separatorInset = UIEdgeInsetsMake(0, 54, 0, 0);
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.accountImageView.image = nil;
    self.textLabel.text = @"";
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
