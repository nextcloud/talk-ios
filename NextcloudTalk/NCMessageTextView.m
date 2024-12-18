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

- (void)insertAdaptiveImageGlyph:(NSAdaptiveImageGlyph *)adaptiveImageGlyph replacementRange:(UITextRange *)replacementRange API_AVAILABLE(ios(18.0)) {
    NSDictionary *userInfo = @{
        SLKTextViewPastedItemMediaType: @(SLKPastableMediaTypePNG),
        SLKTextViewPastedItemData: adaptiveImageGlyph.imageContent
    };

    [[NSNotificationCenter defaultCenter] postNotificationName:SLKTextViewDidPasteItemNotification object:nil userInfo:userInfo];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    // Hide iOS-native "Format" option, which is shown, because we enabled allowsEditingTextAttributes for Memoji/Genmoji support
    if (action == NSSelectorFromString(@"_showTextFormattingOptions:") ||
        action == NSSelectorFromString(@"toggleBoldface:") ||
        action == NSSelectorFromString(@"toggleItalics:") ||
        action == NSSelectorFromString(@"toggleUnderline:")) {

        return false;
    }

    return [super canPerformAction:action withSender:sender];
}

@end
