//
//  AccountTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 30.10.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kAccountCellIdentifier;
extern NSString *const kAccountTableViewCellNibName;

@interface AccountTableViewCell : UITableViewCell

@property(nonatomic, weak) IBOutlet UIImageView *accountImageView;
@property (weak, nonatomic) IBOutlet UILabel *accountNameLabel;
@property (weak, nonatomic) IBOutlet UILabel *accountServerLabel;

@end

NS_ASSUME_NONNULL_END
