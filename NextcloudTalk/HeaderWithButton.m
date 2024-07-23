/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "HeaderWithButton.h"

@interface HeaderWithButton ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation HeaderWithButton

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"HeaderWithButton" owner:self options:nil];

        _label.textColor = [UIColor secondaryLabelColor];
        
        [self addSubview:self.contentView];
        
        if ([UIView userInterfaceLayoutDirectionForSemanticContentAttribute:_label.semanticContentAttribute] == UIUserInterfaceLayoutDirectionRightToLeft) {
            _label.textAlignment = NSTextAlignmentRight;
            _button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        } else {
            _label.textAlignment = NSTextAlignmentLeft;
            _button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        }
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

@end
