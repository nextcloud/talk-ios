//
//  RoundedNumberView.m
//  VideoCalls
//
//  Created by Ivan Sein on 18.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "RoundedNumberView.h"

#define kRoundedNumberViewImportantBackgroundColor  [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0] //#0082C9
#define kRoundedNumberViewImportantTextColor        [UIColor whiteColor]
#define kRoundedNumberViewDefaultBackgroundColor    [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0] //#d5d5d5
#define kRoundedNumberViewDefaultTextColor          [UIColor blackColor]
#define kRoundedNumberViewCounterLimit              99

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
    BOOL wider = self.numberLabel.frame.size.width >= self.numberLabel.frame.size.height;
    CGFloat frameWidth = self.numberLabel.frame.size.width * 5/3;
    CGFloat frameHeight = self.numberLabel.frame.size.height + self.numberLabel.frame.size.height / 2;
    self.frame = CGRectMake(0, 0, (wider) ? frameWidth : frameHeight, frameHeight);
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

- (void)setImportant:(BOOL)important
{
    _important = important;
    self.backgroundColor = _important ? kRoundedNumberViewImportantBackgroundColor : kRoundedNumberViewDefaultBackgroundColor;
    _numberColor = _important ? kRoundedNumberViewImportantTextColor : kRoundedNumberViewDefaultTextColor;
}

@end
