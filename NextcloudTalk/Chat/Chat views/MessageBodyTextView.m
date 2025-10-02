/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "MessageBodyTextView.h"

#import "NCRoomsManager.h"
#import "NCUserDefaults.h"

#import "NextcloudTalk-Swift.h"

@implementation MessageBodyTextView

- (instancetype)init
{
    NSTextStorage *textStorage = [NSTextStorage new];

    NSLayoutManager *layoutManager = (NSLayoutManager *)[SwiftMarkdownObjCBridge getLayoutManager];
    [textStorage addLayoutManager: layoutManager];

    NSTextContainer *textContainer = [NSTextContainer new];
    [layoutManager addTextContainer: textContainer];

    self = [[MessageBodyTextView alloc] initWithFrame:CGRectZero textContainer:textContainer];

    if (!self) {
        return nil;
    }

    self.dataDetectorTypes = UIDataDetectorTypeAll;
    self.textContainer.lineFragmentPadding = 0;
    self.textContainerInset = UIEdgeInsetsZero;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // Set background color to clear to allow cell selection color to be visible
    self.backgroundColor = [UIColor clearColor];
    self.editable = NO;
    self.scrollEnabled = NO;
    self.delegate = self;
    return self;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    return NO;
}

// https://stackoverflow.com/a/44878203
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    UITextPosition *position = [self closestPositionToPoint:point];
    if (!position) {return NO;}
    UITextRange *range = [self.tokenizer rangeEnclosingPosition:position withGranularity:UITextGranularityCharacter inDirection:(UITextDirection)UITextLayoutDirectionLeft];
    if (!range) {return NO;}
    NSInteger startIndex = [self offsetFromPosition:self.beginningOfDocument toPosition:range.start];
    return [self.attributedText attribute:NSLinkAttributeName atIndex:startIndex effectiveRange:nil] != nil;
}

#pragma mark - UITextView delegate

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(nonnull NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction
{
    if ([NCUtils isInstanceRoomLinkWithLink:URL.absoluteString]) {
        NSString *token = URL.lastPathComponent;
        [[NCRoomsManager sharedInstance] startChatWithRoomToken:token];
        return NO;
    }
    return YES;
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    if(!NSEqualRanges(textView.selectedRange, NSMakeRange(0, 0))) {
        textView.selectedRange = NSMakeRange(0, 0);
    }
}

@end
