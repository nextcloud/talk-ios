//
//  ContactsTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 18.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "ContactsTableViewCell.h"

#import "UIImageView+AFNetworking.h"

NSString *const kContactCellIdentifier = @"ContactCellIdentifier";
NSString *const kContactsTableCellNibName = @"ContactsTableViewCell";

CGFloat const kContactsTableCellHeight = 72.0f;
CGFloat const kContactsTableCellTitleFontSize = 17.0f;

@implementation ContactsTableViewCell

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
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.contactImage cancelImageDownloadTask];
    self.contactImage.image = nil;
    
    self.labelTitle.text = @"";
    self.labelTitle.textColor = [UIColor darkTextColor];
    self.labelTitle.font = [UIFont systemFontOfSize:kContactsTableCellTitleFontSize weight:UIFontWeightRegular];
}

@end
