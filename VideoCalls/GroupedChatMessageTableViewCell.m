//
//  GroupedChatMessageTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 02.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "GroupedChatMessageTableViewCell.h"
#import "SLKUIConstants.h"

@implementation GroupedChatMessageTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor whiteColor];
        
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    [self.contentView addSubview:self.bodyLabel];
    
    NSDictionary *views = @{@"bodyLabel": self.bodyLabel};
    
    NSDictionary *metrics = @{@"avatar": @45,
                              @"right": @10,
                              @"left": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatar-[bodyLabel(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[bodyLabel(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    CGFloat pointSize = [GroupedChatMessageTableViewCell defaultFontSize];
    
    self.bodyLabel.font = [UIFont systemFontOfSize:pointSize];
    
    self.bodyLabel.text = @"";
}

#pragma mark - Getters

- (UILabel *)bodyLabel
{
    if (!_bodyLabel) {
        _bodyLabel = [UILabel new];
        _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _bodyLabel.backgroundColor = [UIColor clearColor];
        _bodyLabel.userInteractionEnabled = NO;
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.textColor = [UIColor darkGrayColor];
        _bodyLabel.font = [UIFont systemFontOfSize:[GroupedChatMessageTableViewCell defaultFontSize]];
    }
    return _bodyLabel;
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}

@end
