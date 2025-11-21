//
//  UIBarButtonItem+Badge.h
//  therichest
//
//  Created by Mike on 2014-05-05.
//  Copyright (c) 2014 Valnet Inc. All rights reserved.
//
//
//  https://github.com/mikeMTOL/UIBarButtonItem-Badge
//
//  SPDX-FileCopyrightText: 2014 Mike, Valnet Inc.
//  SPDX-License-Identifier: MIT

#import <UIKit/UIKit.h>

@interface UIBarButtonItem (LegacyBadge)

@property (strong, atomic) UILabel *legacyBadge;

// Badge value to be display
@property (nonatomic) NSString *legacyBadgeValue;
// Badge background color
@property (nonatomic) UIColor *legacyBadgeBGColor;
// Badge text color
@property (nonatomic) UIColor *legacyBadgeTextColor;
// Badge font
@property (nonatomic) UIFont *legacyBadgeFont;
// Padding value for the badge
@property (nonatomic) CGFloat legacyBadgePadding;
// Minimum size badge to small
@property (nonatomic) CGFloat legacyBadgeMinSize;
// Values for offseting the badge over the BarButtonItem you picked
@property (nonatomic) CGFloat legacyBadgeOriginX;
@property (nonatomic) CGFloat legacyBadgeOriginY;
// In case of numbers, remove the badge when reaching zero
@property BOOL shouldHideLegacyBadgeAtZero;
// Badge has a bounce animation when value changes
@property BOOL shouldAnimateLegacyBadge;

@end
