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
    [self.contentView addSubview:self.bodyTextView];
    
    NSDictionary *views = @{@"bodyTextView": self.bodyTextView};
    
    NSDictionary *metrics = @{@"avatar": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatar-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    CGFloat pointSize = [GroupedChatMessageTableViewCell defaultFontSize];
    
    self.bodyTextView.font = [UIFont systemFontOfSize:pointSize];
    
    self.bodyTextView.text = @"";
}

#pragma mark - Getters

- (UITextView *)bodyTextView
{
    if (!_bodyTextView) {
        _bodyTextView = [UITextView new];
        _bodyTextView.dataDetectorTypes = UIDataDetectorTypeAll;
        _bodyTextView.textContainer.lineFragmentPadding = 0;
        _bodyTextView.textContainerInset = UIEdgeInsetsZero;
        _bodyTextView.translatesAutoresizingMaskIntoConstraints = NO;
        _bodyTextView.backgroundColor = [UIColor clearColor];
        _bodyTextView.editable= NO;
        _bodyTextView.textColor = [UIColor darkGrayColor];
        _bodyTextView.font = [UIFont systemFontOfSize:[GroupedChatMessageTableViewCell defaultFontSize]];
    }
    return _bodyTextView;
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
//    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
//    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}

@end
