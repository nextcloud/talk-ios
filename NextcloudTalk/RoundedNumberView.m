/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
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
