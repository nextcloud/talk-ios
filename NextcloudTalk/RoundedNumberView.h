/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, HighlightType) {
    kHighlightTypeNone = 0,
    kHighlightTypeBorder,
    kHighlightTypeImportant
};

@interface RoundedNumberView : UIView

@property (nonatomic, assign) NSInteger number;
@property (nonatomic, strong) UIColor *numberColor;
@property (nonatomic, assign) HighlightType highlightType;

@end
