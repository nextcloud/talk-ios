//
//  UserSettingsTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 16.01.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "UserSettingsTableViewCell.h"

NSString *const kUserSettingsCellIdentifier = @"UserSettingsCellIdentifier";
NSString *const kUserSettingsTableCellNibName = @"UserSettingsTableViewCell";

@implementation UserSettingsTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.userImageView.layer.cornerRadius = 40.0;
    self.userImageView.layer.masksToBounds = YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)setUserStatus:(NSString *)userStatus
{
    UIImage *statusImage = nil;
    if ([userStatus isEqualToString:@"online"]) {
        statusImage = [UIImage imageNamed:@"user-status-online-24"];
    } else if ([userStatus isEqualToString:@"away"]) {
        statusImage = [UIImage imageNamed:@"user-status-away-24"];
    } else if ([userStatus isEqualToString:@"dnd"]) {
        statusImage = [UIImage imageNamed:@"user-status-dnd-24"];
    }
    
    if (statusImage) {
        [_userStatusImageView setImage:statusImage];
        _userStatusImageView.contentMode = UIViewContentModeCenter;
        _userStatusImageView.layer.cornerRadius = 16;
        _userStatusImageView.clipsToBounds = YES;
        // TODO: Change it when dark mode is implemented
        _userStatusImageView.backgroundColor = [UIColor whiteColor];
    }
}

@end
