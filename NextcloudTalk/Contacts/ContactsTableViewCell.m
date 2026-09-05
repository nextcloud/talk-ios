/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ContactsTableViewCell.h"
#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

NSString *const kContactCellIdentifier = @"ContactCellIdentifier";
NSString *const kContactsTableCellNibName = @"ContactsTableViewCell";

CGFloat const kContactsTableCellHeight = 72.0f;
CGFloat const kContactsTableCellTitleFontSize = 17.0f;
static CGFloat const kContactsTableCellRoleIconSize = 15.0f;
static CGFloat const kContactsTableCellRoleIconSpacing = 4.0f;

@interface ContactsTableViewCell ()

@property (weak, nonatomic) IBOutlet UIStackView *titleStackView;
@property (nonatomic, strong) NSLayoutConstraint *roleIconLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *roleIconWidthConstraint;

@end

@implementation ContactsTableViewCell

- (void)awakeFromNib
{
    [super awakeFromNib];

    [self setupRoleIconView];
}

- (void)setupRoleIconView
{
    self.roleIconView = [[UIImageView alloc] init];
    self.roleIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.roleIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.roleIconView.tintColor = [UIColor secondaryLabelColor];
    [self.roleIconView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:self.roleIconView];

    // The labels are leading-aligned in their stack view and hug their text, so the
    // icon can follow the name directly instead of sitting at the edge of the cell
    self.roleIconLeadingConstraint = [self.roleIconView.leadingAnchor constraintEqualToAnchor:self.labelTitle.trailingAnchor];
    self.roleIconWidthConstraint = [self.roleIconView.widthAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        self.roleIconLeadingConstraint,
        self.roleIconWidthConstraint,
        [self.roleIconView.centerYAnchor constraintEqualToAnchor:self.labelTitle.centerYAnchor],
        // Truncate the name rather than the icon
        [self.roleIconView.trailingAnchor constraintLessThanOrEqualToAnchor:self.titleStackView.trailingAnchor],
        [self.labelTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.titleStackView.trailingAnchor],
        [self.userStatusMessageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.titleStackView.trailingAnchor]
    ]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.avatarView prepareForReuse];

    self.userStatusMessageLabel.text = @"";
    self.userStatusMessageLabel.hidden = YES;
    
    self.labelTitle.text = @"";
    self.labelTitle.textColor = [UIColor labelColor];
    
    self.labelTitle.font = [UIFont systemFontOfSize:kContactsTableCellTitleFontSize weight:UIFontWeightRegular];

    [self setRoleIcon:nil withAccessibilityLabel:nil];
}

- (void)setRoleIcon:(NSString *)systemImageName withAccessibilityLabel:(NSString *)accessibilityLabel
{
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:kContactsTableCellRoleIconSize];
    UIImage *icon = systemImageName ? [UIImage systemImageNamed:systemImageName withConfiguration:configuration] : nil;

    self.roleIconView.image = icon;
    self.roleIconView.accessibilityLabel = accessibilityLabel;

    // Without an icon the view collapses so it takes no space after the name
    self.roleIconLeadingConstraint.constant = icon ? kContactsTableCellRoleIconSpacing : 0;
    self.roleIconWidthConstraint.constant = icon.size.width;
}

- (void)setUserStatusMessage:(NSString *)userStatusMessage withIcon:(NSString *)userStatusIcon
{
    if (userStatusMessage && ![userStatusMessage isEqualToString:@""]) {
        self.userStatusMessageLabel.text = userStatusMessage;
        if (userStatusIcon && ![userStatusIcon isEqualToString:@""]) {
            self.userStatusMessageLabel.text = [NSString stringWithFormat:@"%@ %@", userStatusIcon, userStatusMessage];
        }
        self.userStatusMessageLabel.hidden = NO;
    } else {
        self.userStatusMessageLabel.hidden = YES;
    }
}

@end
