/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "MessageBodyTextView.h"

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

    [self commonInit];

    return self;
}

- (void)commonInit
{
    self.dataDetectorTypes = UIDataDetectorTypeAll;
    self.textContainer.lineFragmentPadding = 0;
    self.textContainerInset = UIEdgeInsetsZero;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // Set background color to clear to allow cell selection color to be visible
    self.backgroundColor = [UIColor clearColor];
    self.editable = NO;
    self.scrollEnabled = NO;
    self.delegate = self;
}

- (void)awakeFromNib
{
    // Note: Init from storyboard my still be TextKit2, since there's no custom layout manager
    [super awakeFromNib];
    [self commonInit];
}

- (CGSize)intrinsicContentSize {
    CGSize superSize = [super intrinsicContentSize];

    // When a paragraphStyle with firstLineHeadIndent/headIndent is used, the
    // intrinsicContentSize might not be accurate and the last word/character is wrapped,
    // due to the size being too small. In that case usedRectForTextContainer reports
    // a non-zero x value, we add to the width of the intrinsicContentSize
    if (superSize.width < UINT16_MAX) {
        CGRect usedRect = [self.layoutManager usedRectForTextContainer:self.textContainer];

        if (usedRect.origin.x > 0) {
            return CGSizeMake(superSize.width + usedRect.origin.x, superSize.height);
        }
    }

    return superSize;
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
        [[NCRoomsManager shared] startChatWithRoomToken:token];
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
