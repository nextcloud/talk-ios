//
//  ChatMessageTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 24.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "ChatMessageTableViewCell.h"
#import "OpenInFirefoxControllerObjC.h"
#import "SLKUIConstants.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"
#import "NCSettingsController.h"

@interface ChatMessageTableViewCell () <UITextViewDelegate>
@end

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
    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kChatMessageCellAvatarHeight, kChatMessageCellAvatarHeight)];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.userInteractionEnabled = NO;
    _avatarView.backgroundColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
    _avatarView.layer.cornerRadius = kChatMessageCellAvatarHeight/2.0;
    _avatarView.layer.masksToBounds = YES;
    [self.contentView addSubview:_avatarView];
    
    [self.contentView addSubview:self.titleLabel];
    [self.contentView addSubview:self.dateLabel];
    [self.contentView addSubview:self.bodyTextView];
    
    NSDictionary *views = @{@"avatarView": self.avatarView,
                            @"titleLabel": self.titleLabel,
                            @"dateLabel": self.dateLabel,
                            @"bodyTextView": self.bodyTextView,
                            };
    
    NSDictionary *metrics = @{@"avatarSize": @(kChatMessageCellAvatarHeight),
                              @"padding": @15,
                              @"right": @10,
                              @"left": @5
                              };
    
    if ([self.reuseIdentifier isEqualToString:ChatMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[titleLabel]-[dateLabel(40)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(28)]-left-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(28)]-left-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
    }
    else {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[titleLabel]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[titleLabel]|" options:0 metrics:metrics views:views]];
    }
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarView(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    CGFloat pointSize = [ChatMessageTableViewCell defaultFontSize];
    
    self.titleLabel.font = [UIFont systemFontOfSize:pointSize];
    self.bodyTextView.font = [UIFont systemFontOfSize:pointSize];
    
    self.titleLabel.text = @"";
    self.bodyTextView.text = @"";
    self.dateLabel.text = @"";
    
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

- (MessageBodyTextView *)bodyTextView
{
    if (!_bodyTextView) {
        _bodyTextView = [MessageBodyTextView new];
        _bodyTextView.delegate = self;
        _bodyTextView.font = [UIFont systemFontOfSize:[ChatMessageTableViewCell defaultFontSize]];
    }
    return _bodyTextView;
}

- (void)setGuestAvatar:(NSString *)displayName
{
    UIColor *guestAvatarColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
    NSString *name = ([displayName isEqualToString:@""]) ? @"?" : displayName;
    [_avatarView setImageWithString:name color:guestAvatarColor circular:true];
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
//    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
//    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}

#pragma mark - UITextView delegate

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(nonnull NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction
{
    if ([[NCSettingsController sharedInstance].defaultBrowser isEqualToString:@"Firefox"] && [[OpenInFirefoxControllerObjC sharedInstance] isFirefoxInstalled]) {
        [[OpenInFirefoxControllerObjC sharedInstance] openInFirefox:URL];
        return NO;
    }
    return YES;
}

@end
