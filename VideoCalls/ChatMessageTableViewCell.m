//
//  ChatMessageTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 24.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "ChatMessageTableViewCell.h"
#import "SLKUIConstants.h"
#import "UIImageView+AFNetworking.h"

@implementation ChatMessageTableViewCell

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
    [self.contentView addSubview:self.thumbnailView];
    [self.contentView addSubview:self.titleLabel];
    [self.contentView addSubview:self.dateLabel];
    [self.contentView addSubview:self.bodyLabel];
    
    NSDictionary *views = @{@"thumbnailView": self.thumbnailView,
                            @"titleLabel": self.titleLabel,
                            @"dateLabel": self.dateLabel,
                            @"bodyLabel": self.bodyLabel,
                            };
    
    NSDictionary *metrics = @{@"tumbSize": @(kChatMessageCellAvatarHeight),
                              @"padding": @15,
                              @"right": @10,
                              @"left": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[thumbnailView(tumbSize)]-right-[titleLabel]-[dateLabel]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"[titleLabel(==dateLabel)]" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[thumbnailView(tumbSize)]-right-[bodyLabel(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[thumbnailView(tumbSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    
    if ([self.reuseIdentifier isEqualToString:ChatMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(28)]-left-[bodyLabel(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(28)]-left-[bodyLabel(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
    }
    else {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[titleLabel]|" options:0 metrics:metrics views:views]];
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    CGFloat pointSize = [ChatMessageTableViewCell defaultFontSize];
    
    self.titleLabel.font = [UIFont systemFontOfSize:pointSize];
    self.bodyLabel.font = [UIFont systemFontOfSize:pointSize];
    
    self.titleLabel.text = @"";
    self.bodyLabel.text = @"";
    
    [self.avatarView cancelImageDownloadTask];
    self.avatarView.image = nil;
}

#pragma mark - Getters

- (UILabel *)titleLabel
{
    if (!_titleLabel) {
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.userInteractionEnabled = NO;
        _titleLabel.numberOfLines = 0;
        _titleLabel.textColor = [UIColor lightGrayColor];
        _titleLabel.font = [UIFont systemFontOfSize:[ChatMessageTableViewCell defaultFontSize]];
    }
    return _titleLabel;
}

- (UILabel *)dateLabel
{
    if (!_dateLabel) {
        _dateLabel = [UILabel new];
        _dateLabel.textAlignment = NSTextAlignmentRight;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.backgroundColor = [UIColor clearColor];
        _dateLabel.userInteractionEnabled = NO;
        _dateLabel.numberOfLines = 0;
        _dateLabel.textColor = [UIColor lightGrayColor];
        _dateLabel.font = [UIFont systemFontOfSize:12.0];
    }
    return _dateLabel;
}

- (UILabel *)bodyLabel
{
    if (!_bodyLabel) {
        _bodyLabel = [UILabel new];
        _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _bodyLabel.backgroundColor = [UIColor clearColor];
        _bodyLabel.userInteractionEnabled = NO;
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.textColor = [UIColor darkGrayColor];
        _bodyLabel.font = [UIFont systemFontOfSize:[ChatMessageTableViewCell defaultFontSize]];
    }
    return _bodyLabel;
}

- (UIImageView *)thumbnailView
{
    if (!_avatarView) {
        _avatarView = [UIImageView new];
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarView.userInteractionEnabled = NO;
        _avatarView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        
        _avatarView.layer.cornerRadius = kChatMessageCellAvatarHeight/2.0;
        _avatarView.layer.masksToBounds = YES;
    }
    return _avatarView;
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
//    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
//    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}

@end
