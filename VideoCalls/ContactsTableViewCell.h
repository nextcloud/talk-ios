//
//  ContactsTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 18.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const kContactCellIdentifier;
extern NSString *const kContactsTableCellNibName;

extern CGFloat const kContactsTableCellHeight;
extern CGFloat const kContactsTableCellTitleFontSize;

@interface ContactsTableViewCell : UITableViewCell

@property(nonatomic, weak) IBOutlet UIImageView *contactImage;
@property(nonatomic, weak) IBOutlet UILabel *labelTitle;
@property (weak, nonatomic) IBOutlet UIImageView *userStatusImageView;

- (void)setUserStatus:(NSString *)userStatus;

@end
