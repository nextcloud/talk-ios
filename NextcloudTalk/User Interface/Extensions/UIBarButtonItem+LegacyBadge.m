//
//  UIBarButtonItem+Badge.m
//  therichest
//
//  Created by Mike on 2014-05-05.
//  Copyright (c) 2014 Valnet Inc. All rights reserved.
//
//  https://github.com/mikeMTOL/UIBarButtonItem-Badge
//
//  SPDX-FileCopyrightText: 2014 Mike, Valnet Inc.
//  SPDX-License-Identifier: MIT
//
#import <objc/runtime.h>
#import "UIBarButtonItem+LegacyBadge.h"

NSString const *UIBarButtonItem_legacyBadgeKey = @"UIBarButtonItem_legacyBadgeKey";

NSString const *UIBarButtonItem_legacyBadgeBGColorKey = @"UIBarButtonItem_legacyBadgeBGColorKey";
NSString const *UIBarButtonItem_legacyBadgeTextColorKey = @"UIBarButtonItem_legacyBadgeTextColorKey";
NSString const *UIBarButtonItem_legacyBadgeFontKey = @"UIBarButtonItem_legacyBadgeFontKey";
NSString const *UIBarButtonItem_legacyBadgePaddingKey = @"UIBarButtonItem_legacyBadgePaddingKey";
NSString const *UIBarButtonItem_legacyBadgeMinSizeKey = @"UIBarButtonItem_legacyBadgeMinSizeKey";
NSString const *UIBarButtonItem_legacyBadgeOriginXKey = @"UIBarButtonItem_legacyBadgeOriginXKey";
NSString const *UIBarButtonItem_legacyBadgeOriginYKey = @"UIBarButtonItem_legacyBadgeOriginYKey";
NSString const *UIBarButtonItem_shouldHideLegacyBadgeAtZeroKey = @"UIBarButtonItem_shouldHideLegacyBadgeAtZeroKey";
NSString const *UIBarButtonItem_shouldAnimateLegacyBadgeKey = @"UIBarButtonItem_shouldAnimateLegacyBadgeKey";
NSString const *UIBarButtonItem_legacyBadgeValueKey = @"UIBarButtonItem_legacyBadgeValueKey";

@implementation UIBarButtonItem (LegacyBadge)

@dynamic legacyBadgeValue, legacyBadgeBGColor, legacyBadgeTextColor, legacyBadgeFont;
@dynamic legacyBadgePadding, legacyBadgeMinSize, legacyBadgeOriginX, legacyBadgeOriginY;
@dynamic shouldHideLegacyBadgeAtZero, shouldAnimateLegacyBadge;

- (void)legacyBadgeInit
{
    UIView *superview = nil;
    CGFloat defaultOriginX = 0;
    if (self.customView) {
        superview = self.customView;
        defaultOriginX = superview.frame.size.width - self.legacyBadge.frame.size.width/2;
        // Avoids badge to be clipped when animating its scale
        superview.clipsToBounds = NO;
    } else if ([self respondsToSelector:@selector(view)] && [(id)self view]) {
        superview = [(id)self view];
        defaultOriginX = superview.frame.size.width - self.legacyBadge.frame.size.width;
    }
    [superview addSubview:self.legacyBadge];

    // Default design initialization
    self.legacyBadgeBGColor   = [UIColor redColor];
    self.legacyBadgeTextColor = [UIColor whiteColor];
    self.legacyBadgeFont      = [UIFont systemFontOfSize:12.0];
    self.legacyBadgePadding   = 6;
    self.legacyBadgeMinSize   = 8;
    self.legacyBadgeOriginX   = defaultOriginX;
    self.legacyBadgeOriginY   = -4;
    self.shouldHideLegacyBadgeAtZero = YES;
    self.shouldAnimateLegacyBadge = YES;
}

#pragma mark - Utility methods

// Handle badge display when its properties have been changed (color, font, ...)
- (void)refreshLegacyBadge
{
    // Change new attributes
    self.legacyBadge.textColor        = self.legacyBadgeTextColor;
    self.legacyBadge.backgroundColor  = self.legacyBadgeBGColor;
    self.legacyBadge.font             = self.legacyBadgeFont;

    if (!self.legacyBadge || [self.legacyBadgeValue isEqualToString:@""] || ([self.legacyBadgeValue isEqualToString:@"0"] && self.shouldHideLegacyBadgeAtZero)) {
        self.legacyBadge.hidden = YES;
    } else {
        self.legacyBadge.hidden = NO;
        [self updateLegacyBadgeValueAnimated:YES];
    }

}

- (CGSize)legacyBadgeExpectedSize
{
    // When the value changes the badge could need to get bigger
    // Calculate expected size to fit new value
    // Use an intermediate label to get expected size thanks to sizeToFit
    // We don't call sizeToFit on the true label to avoid bad display
    UILabel *frameLabel = [self duplicateLabel:self.legacyBadge];
    [frameLabel sizeToFit];

    CGSize expectedLabelSize = frameLabel.frame.size;
    return expectedLabelSize;
}

- (void)updateLegacyBadgeFrame
{

    CGSize expectedLabelSize = [self legacyBadgeExpectedSize];

    // Make sure that for small value, the badge will be big enough
    CGFloat minHeight = expectedLabelSize.height;

    // Using a const we make sure the badge respect the minimum size
    minHeight = (minHeight < self.legacyBadgeMinSize) ? self.legacyBadgeMinSize : expectedLabelSize.height;
    CGFloat minWidth = expectedLabelSize.width;
    CGFloat padding = self.legacyBadgePadding;

    // Using const we make sure the badge doesn't get too smal
    minWidth = (minWidth < minHeight) ? minHeight : expectedLabelSize.width;
    self.legacyBadge.layer.masksToBounds = YES;
    self.legacyBadge.frame = CGRectMake(self.legacyBadgeOriginX, self.legacyBadgeOriginY, minWidth + padding, minHeight + padding);
    self.legacyBadge.layer.cornerRadius = (minHeight + padding) / 2;
}

// Handle the badge changing value
- (void)updateLegacyBadgeValueAnimated:(BOOL)animated
{
    // Bounce animation on badge if value changed and if animation authorized
    if (animated && self.shouldAnimateLegacyBadge && ![self.legacyBadge.text isEqualToString:self.legacyBadgeValue]) {
        CABasicAnimation * animation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        [animation setFromValue:[NSNumber numberWithFloat:1.5]];
        [animation setToValue:[NSNumber numberWithFloat:1]];
        [animation setDuration:0.2];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithControlPoints:.4f :1.3f :1.f :1.f]];
        [self.legacyBadge.layer addAnimation:animation forKey:@"bounceAnimation"];
    }

    // Set the new value
    self.legacyBadge.text = self.legacyBadgeValue;

    // Animate the size modification if needed
    if (animated && self.shouldAnimateLegacyBadge) {
        [UIView animateWithDuration:0.2 animations:^{
            [self updateLegacyBadgeFrame];
        }];
    } else {
        [self updateLegacyBadgeFrame];
    }
}

- (UILabel *)duplicateLabel:(UILabel *)labelToCopy
{
    UILabel *duplicateLabel = [[UILabel alloc] initWithFrame:labelToCopy.frame];
    duplicateLabel.text = labelToCopy.text;
    duplicateLabel.font = labelToCopy.font;

    return duplicateLabel;
}

- (void)removeLegacyBadge
{
    // Animate badge removal
    [UIView animateWithDuration:0.2 animations:^{
        self.legacyBadge.transform = CGAffineTransformMakeScale(0, 0);
    } completion:^(BOOL finished) {
        [self.legacyBadge removeFromSuperview];
        self.legacyBadge = nil;
    }];
}

#pragma mark - getters/setters

-(UILabel*)legacyBadge {
    UILabel* lbl = objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeKey);
    if(lbl==nil) {
        lbl = [[UILabel alloc] initWithFrame:CGRectMake(self.legacyBadgeOriginX, self.legacyBadgeOriginY, 20, 20)];
        [self setLegacyBadge:lbl];
        [self legacyBadgeInit];
        [self.customView addSubview:lbl];
        lbl.textAlignment = NSTextAlignmentCenter;
    }
    return lbl;
}

-(void)setLegacyBadge:(UILabel *)badgeLabel
{
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeKey, badgeLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Badge value to be display
-(NSString *)legacyBadgeValue {
    return objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeValueKey);
}

-(void)setLegacyBadgeValue:(NSString *)badgeValue
{
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeValueKey, badgeValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // When changing the badge value check if we need to remove the badge
    [self updateLegacyBadgeValueAnimated:YES];
    [self refreshLegacyBadge];
}

// Badge background color
-(UIColor *)legacyBadgeBGColor {
    return objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeBGColorKey);
}

-(void)setLegacyBadgeBGColor:(UIColor *)badgeBGColor
{
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeBGColorKey, badgeBGColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.legacyBadge) {
        [self refreshLegacyBadge];
    }
}

// Badge text color
-(UIColor *)legacyBadgeTextColor {
    return objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeTextColorKey);
}

-(void)setLegacyBadgeTextColor:(UIColor *)badgeTextColor
{
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeTextColorKey, badgeTextColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.legacyBadge) {
        [self refreshLegacyBadge];
    }
}

// Badge font
-(UIFont *)legacyBadgeFont {
    return objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeFontKey);
}

-(void)setLegacyBadgeFont:(UIFont *)badgeFont
{
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeFontKey, badgeFont, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.legacyBadge) {
        [self refreshLegacyBadge];
    }
}

// Padding value for the badge
-(CGFloat)legacyBadgePadding {
    NSNumber *number = objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgePaddingKey);
    return number.floatValue;
}

-(void)setLegacyBadgePadding:(CGFloat)badgePadding
{
    NSNumber *number = [NSNumber numberWithDouble:badgePadding];
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgePaddingKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.legacyBadge) {
        [self updateLegacyBadgeFrame];
    }
}

// Minimum size badge to small
-(CGFloat)legacyBadgeMinSize {
    NSNumber *number = objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeMinSizeKey);
    return number.floatValue;
}

-(void)setLegacyBadgeMinSize:(CGFloat)badgeMinSize
{
    NSNumber *number = [NSNumber numberWithDouble:badgeMinSize];
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeMinSizeKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.legacyBadge) {
        [self updateLegacyBadgeFrame];
    }
}

// Values for offseting the badge over the BarButtonItem you picked
-(CGFloat)legacyBadgeOriginX {
    NSNumber *number = objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeOriginXKey);
    return number.floatValue;
}

-(void)setLegacyBadgeOriginX:(CGFloat)badgeOriginX
{
    NSNumber *number = [NSNumber numberWithDouble:badgeOriginX];
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeOriginXKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.legacyBadge) {
        [self updateLegacyBadgeFrame];
    }
}

-(CGFloat)legacyBadgeOriginY {
    NSNumber *number = objc_getAssociatedObject(self, &UIBarButtonItem_legacyBadgeOriginYKey);
    return number.floatValue;
}

-(void)setLegacyBadgeOriginY:(CGFloat)badgeOriginY
{
    NSNumber *number = [NSNumber numberWithDouble:badgeOriginY];
    objc_setAssociatedObject(self, &UIBarButtonItem_legacyBadgeOriginYKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.legacyBadge) {
        [self updateLegacyBadgeFrame];
    }
}

// In case of numbers, remove the badge when reaching zero
-(BOOL)shouldHideLegacyBadgeAtZero {
    NSNumber *number = objc_getAssociatedObject(self, &UIBarButtonItem_shouldHideLegacyBadgeAtZeroKey);
    return number.boolValue;
}

- (void)setShouldHideLegacyBadgeAtZero:(BOOL)shouldHideBadgeAtZero
{
    NSNumber *number = [NSNumber numberWithBool:shouldHideBadgeAtZero];
    objc_setAssociatedObject(self, &UIBarButtonItem_shouldHideLegacyBadgeAtZeroKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(self.legacyBadge) {
        [self refreshLegacyBadge];
    }
}

// Badge has a bounce animation when value changes
-(BOOL)shouldAnimateLegacyBadge {
    NSNumber *number = objc_getAssociatedObject(self, &UIBarButtonItem_shouldAnimateLegacyBadgeKey);
    return number.boolValue;
}

- (void)setShouldAnimateLegacyBadge:(BOOL)shouldAnimateBadge
{
    NSNumber *number = [NSNumber numberWithBool:shouldAnimateBadge];
    objc_setAssociatedObject(self, &UIBarButtonItem_shouldAnimateLegacyBadgeKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(self.legacyBadge) {
        [self refreshLegacyBadge];
    }
}


@end
