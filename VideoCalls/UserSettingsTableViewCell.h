//
//  UserSettingsTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 16.01.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const kUserSettingsCellIdentifier;
extern NSString *const kUserSettingsTableCellNibName;

@interface UserSettingsTableViewCell : UITableViewCell

@property(nonatomic, weak) IBOutlet UIImageView *userImageView;
@property (weak, nonatomic) IBOutlet UIImageView *userStatusImageView;
@property(nonatomic, weak) IBOutlet UILabel *userDisplayNameLabel;
@property(nonatomic, weak) IBOutlet UILabel *serverAddressLabel;

- (void)setUserStatus:(NSString *)userStatus;

@end
