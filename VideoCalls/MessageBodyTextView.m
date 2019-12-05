//
//  MessageBodyTextView.m
//  VideoCalls
//
//  Created by Ivan Sein on 28.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "MessageBodyTextView.h"
#import "NCSettingsController.h"
#import "OpenInFirefoxControllerObjC.h"

@implementation MessageBodyTextView

- (instancetype)init
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    self.dataDetectorTypes = UIDataDetectorTypeAll;
    self.textContainer.lineFragmentPadding = 0;
    self.textContainerInset = UIEdgeInsetsZero;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [UIColor clearColor];
    self.editable = NO;
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
    if ([[NCSettingsController sharedInstance].defaultBrowser isEqualToString:@"Firefox"] && [[OpenInFirefoxControllerObjC sharedInstance] isFirefoxInstalled]) {
        [[OpenInFirefoxControllerObjC sharedInstance] openInFirefox:URL];
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
