/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCMessageTextView.h"

#import "NCAppBranding.h"

@implementation NCMessageTextView

- (instancetype)init
{
    if (self = [super init]) {
        // Do something
    }
    return self;
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    [super willMoveToSuperview:newSuperview];
    
    self.keyboardType = UIKeyboardTypeDefault;
    
    self.backgroundColor = [NCAppBranding backgroundColor];
    
    self.placeholder = NSLocalizedString(@"Write message, @ to mention someone …", nil);
    self.placeholderColor = [NCAppBranding placeholderColor];
}

@end
