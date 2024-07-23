/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "RoundedNumberView.h"

#import "NCAppBranding.h"

#define kRoundedNumberViewImportantBackgroundColor  [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0] //#0082C9
#define kRoundedNumberViewImportantTextColor        [UIColor whiteColor]
#define kRoundedNumberViewDefaultBackgroundColor    [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0] //#d5d5d5
#define kRoundedNumberViewDefaultTextColor          [UIColor blackColor]
#define kRoundedNumberViewCounterLimit              9999

@interface RoundedNumberView ()
@property (nonatomic, strong) UILabel *numberLabel;
@end

@implementation RoundedNumberView

- (id)initWithFrame:(CGRect)frame
{
    return [self initWithNumber:0];
}


- (id)init
{
    return [self initWithNumber:0];
}


- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        _number = 0;
        [self addNecessaryViews];
        [self setup];
    }
    return self;
}


- (id)initWithNumber:(NSInteger)number
{
    self = [super initWithFrame:CGRectMake(0.0f, 0.0f, 1.0f, 1.0f)];
    if (self) {
        _number = 0;
        [self addNecessaryViews];
        [self setup];
    }
    return self;
}


// This method should be called only once
- (void)addNecessaryViews
{
    self.backgroundColor = kRoundedNumberViewDefaultBackgroundColor;
    self.numberLabel = [[UILabel alloc] init];
    self.numberLabel.font = [UIFont boldSystemFontOfSize:14];
    self.numberLabel.backgroundColor = [UIColor clearColor];
    _numberColor = kRoundedNumberViewDefaultTextColor;
    [self addSubview:self.numberLabel];
}


- (void)setup
{
    NSInteger counter = _number;
    self.numberLabel.textColor = _numberColor;
    self.numberLabel.text = [NSString stringWithFormat:@"%ld", (long)counter];
    if (counter > kRoundedNumberViewCounterLimit) {
        self.numberLabel.text = [NSString stringWithFormat:@"%d+", kRoundedNumberViewCounterLimit];
    }
    [self.numberLabel sizeToFit];
    CGFloat frameWidth = self.numberLabel.frame.size.width + 16;
    CGFloat frameHeight = self.numberLabel.frame.size.height + self.numberLabel.frame.size.height / 2;
    self.frame = CGRectMake(0, 0, (frameWidth >= frameHeight) ? frameWidth : frameHeight, frameHeight);
    self.layer.cornerRadius = self.frame.size.height / 2;
    [self.numberLabel setCenter:CGPointMake(self.frame.size.width / 2, self.frame.size.height / 2)];
}


- (void)setNumber:(NSInteger)number
{
	if (_number != number) {
		_number = number;
        [self setup];
	}
}


- (void)setNumberColor:(UIColor *)numberColor
{
    if (_numberColor != numberColor) {
        _numberColor = numberColor;
        self.numberLabel.textColor = _numberColor;
    }
}

- (void)setHighlightType:(HighlightType)highlightType
{
    _highlightType = highlightType;
    
    self.layer.borderWidth = 0;
    
    switch (highlightType) {
        case kHighlightTypeNone:
            self.backgroundColor = [NCAppBranding placeholderColor];
            _numberColor = nil;
            break;
        case kHighlightTypeBorder:
            self.backgroundColor = [UIColor systemBackgroundColor];
            _numberColor = [NCAppBranding elementColor];
            self.layer.borderWidth = 2;
            self.layer.borderColor = [NCAppBranding elementColor].CGColor;
            break;
        case kHighlightTypeImportant:
            self.backgroundColor = [NCAppBranding themeColor];
            _numberColor = [NCAppBranding themeTextColor];
            break;
    }
}

@end
