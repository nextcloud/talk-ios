//
//  ContactsTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 18.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "ContactsTableViewCell.h"

NSString *const kContactCellIdentifier = @"ContactCellIdentifier";
NSString *const kContactsTableCellNibName = @"ContactsTableViewCell";

@implementation ContactsTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
