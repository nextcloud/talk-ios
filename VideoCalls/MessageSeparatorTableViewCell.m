//
//  MessageSeparatorTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 05.09.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "MessageSeparatorTableViewCell.h"

@implementation MessageSeparatorTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1];
        self.messageId = kMessageSeparatorIdentifier;
        
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    [self.contentView addSubview:self.separatorLabel];
    
    NSDictionary *views = @{@"separatorLabel": self.separatorLabel};
    
    NSDictionary *metrics = @{@"left": @10,
                              @"top": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-left-[separatorLabel(>=0)]-left-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-top-[separatorLabel(14)]-top-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
}

#pragma mark - Getters

- (UILabel *)separatorLabel
{
    if (!_separatorLabel) {
        _separatorLabel = [UILabel new];
        _separatorLabel.textAlignment = NSTextAlignmentCenter;
        _separatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _separatorLabel.backgroundColor = [UIColor clearColor];
        _separatorLabel.userInteractionEnabled = NO;
        _separatorLabel.numberOfLines = 1;
        _separatorLabel.textColor = [UIColor whiteColor];
        _separatorLabel.font = [UIFont systemFontOfSize:12.0];
        _separatorLabel.text = @"Last read message";
    }
    return _separatorLabel;
}

@end
