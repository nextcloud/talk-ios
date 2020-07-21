//
//  ShareTableViewCell.h
//  ShareExtension
//
//  Created by Ivan Sein on 20.07.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const kShareCellIdentifier;
extern NSString *const kShareTableCellNibName;

extern CGFloat const kShareTableCellHeight;

@interface ShareAvatarImageView : UIImageView
@end

@interface ShareTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet ShareAvatarImageView *avatarImageView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;

@end
