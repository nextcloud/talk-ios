/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "QuotedMessageView.h"

#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

@interface QuotedMessageView ()
@property (nonatomic, strong) UIView *quoteView;
@end

@implementation QuotedMessageView

- (instancetype)init
{
    self = [super initWithFrame:CGRectMake(0, 0, 50, 50)];
    if (self) {
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    self.backgroundColor = [NCAppBranding backgroundColor];
    self.layer.borderColor = [NCAppBranding placeholderColor].CGColor;
    self.layer.borderWidth = 1.0;
    self.layer.cornerRadius = 8.0;

    [self addSubview:self.quoteView];
    [self addSubview:self.actorLabel];
    [self addSubview:self.messageLabel];
    [self addSubview:self.avatarView];

    
    NSDictionary *views = @{@"quoteView": self.quoteView,
                            @"actorLabel": self.actorLabel,
                            @"messageLabel": self.messageLabel,
                            @"avatarView": self.avatarView
                            };

    NSDictionary *metrics = @{
        @"padding": @8,
        @"avatarSize": @20,
    };
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[quoteView(padding)]-[avatarView(avatarSize)]-padding-[actorLabel]-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[quoteView(padding)]-[messageLabel]-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-padding-[quoteView(44)]-padding-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-padding-[actorLabel(20)]-4-[messageLabel(20)]-padding-|" options:0 metrics:metrics views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-padding-[avatarView(20)]-4-[messageLabel(20)]-padding-|" options:0 metrics:metrics views:views]];
}


#pragma mark - Getters

- (UIView *)quoteView
{
    if (!_quoteView) {
        _quoteView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, 60)];
        _quoteView.translatesAutoresizingMaskIntoConstraints = NO;
        _quoteView.backgroundColor = [UIColor systemFillColor];
        _quoteView.layer.cornerRadius = 4.0;
    }
    return _quoteView;
}

- (UILabel *)actorLabel
{
    if (!_actorLabel) {
        _actorLabel = [UILabel new];
        _actorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _actorLabel.backgroundColor = [UIColor clearColor];
        _actorLabel.userInteractionEnabled = NO;
        _actorLabel.numberOfLines = 1;
        _actorLabel.contentMode = UIViewContentModeLeft;
        
        _actorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _actorLabel.textColor = [UIColor secondaryLabelColor];
    }
    return _actorLabel;
}

- (UILabel *)messageLabel
{
    if (!_messageLabel) {
        _messageLabel = [UILabel new];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.backgroundColor = [UIColor clearColor];
        _messageLabel.userInteractionEnabled = NO;
        _messageLabel.numberOfLines = 0;
        _messageLabel.contentMode = UIViewContentModeLeft;
        
        _messageLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _messageLabel.textColor = [NCAppBranding chatForegroundColor];
    }
    return _messageLabel;
}

- (AvatarImageView *)avatarView
{
    if (!_avatarView) {
        _avatarView = [[AvatarImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarView.layer.cornerRadius = 10;
        _avatarView.layer.masksToBounds = YES;
    }
    return _avatarView;
}

#pragma mark - Setters

- (void)setHighlighted:(BOOL)highlighted
{
    _highlighted = highlighted;
    
    if (_highlighted) {
        _quoteView.backgroundColor = [NCAppBranding themeColor];
    } else {
        _quoteView.backgroundColor = [UIColor systemFillColor];
    }
}


@end
