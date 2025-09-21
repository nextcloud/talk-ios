/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ReplyMessageView.h"

#import "SLKUIConstants.h"

#import "NCAppBranding.h"
#import "NCChatMessage.h"

#import "NextcloudTalk-Swift.h"

@interface ReplyMessageView ()
@property (nonatomic, strong) UIView *quoteContainerView;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) NSLayoutConstraint *cancelButtonWidthConstraint;
@end

@implementation ReplyMessageView
@synthesize visible = _visible;

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    self.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    [self addSubview:self.quoteContainerView];
    [self addSubview:self.cancelButton];
    [self.layer addSublayer:self.topBorder];

    [_quoteContainerView addSubview:self.quotedMessageView];

    self.cancelButtonWidthConstraint = [self.cancelButton.widthAnchor constraintEqualToConstant:44];

    [NSLayoutConstraint activateConstraints:@[
        [self.quoteContainerView.leftAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leftAnchor constant:16],

        [self.cancelButton.leftAnchor constraintEqualToAnchor:self.quoteContainerView.rightAnchor constant:4],

        [self.cancelButton.rightAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.rightAnchor constant:-4],
        self.cancelButtonWidthConstraint,
        [self.quotedMessageView.widthAnchor constraintEqualToAnchor:self.quoteContainerView.widthAnchor],

        [self.quoteContainerView.topAnchor constraintEqualToAnchor:self.quoteContainerView.superview.topAnchor],
        [self.quoteContainerView.bottomAnchor constraintEqualToAnchor:self.quoteContainerView.superview.bottomAnchor],

        [self.cancelButton.topAnchor constraintEqualToAnchor:self.cancelButton.superview.topAnchor],
        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.cancelButton.superview.bottomAnchor],

        [self.quotedMessageView.centerYAnchor constraintEqualToAnchor:self.quoteContainerView.centerYAnchor]
    ]];
}

#pragma mark - UIView

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    self.topBorder.frame = CGRectMake(0, 0, self.bounds.size.width, 1);
}

- (CGSize)intrinsicContentSize
{
    // This will indicate the size of the view when calling systemLayoutSizeFittingSize in SLKTextViewController
    // QuoteMessageView(60) + 2*Padding(8)
    return CGSizeMake(UIViewNoIntrinsicMetric, 76);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    if (_topBorder && [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        // We use a CGColor so we loose the automatic color changing of dynamic colors -> update manually
        _topBorder.backgroundColor = [UIColor quaternarySystemFillColor].CGColor;
    }
}


#pragma mark - SLKReplyViewProtocol

- (void)dismiss
{
    if (self.isVisible) {
        self.visible = NO;
    }
}


#pragma mark - Getters

- (UIView *)quoteContainerView
{
    if (!_quoteContainerView) {
        _quoteContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
        _quoteContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _quoteContainerView;
}


- (QuotedMessageView *)quotedMessageView
{
    if (!_quotedMessageView) {
        _quotedMessageView = [[QuotedMessageView alloc] init];
        _quotedMessageView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _quotedMessageView;
}

- (UIButton *)cancelButton
{
    if (!_cancelButton) {
        _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        _cancelButton.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
        [_cancelButton setImage:[UIImage systemImageNamed:@"xmark.circle"] forState:UIControlStateNormal];
        [_cancelButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    }
    return _cancelButton;
}

- (CALayer *)topBorder
{
    if (!_topBorder) {
        _topBorder = [CAGradientLayer layer];
        _topBorder.frame = CGRectMake(0.0, 0.0, self.frame.size.width, 1);
        _topBorder.backgroundColor = [UIColor quaternarySystemFillColor].CGColor;
    }
    return _topBorder;
}


#pragma mark - ReplyMessageView

- (void)presentReplyViewWithMessage:(NCChatMessage *)message withUserId:(NSString *)userId
{
    if (!message) {
        return;
    }
    
    self.message = message;
    self.quotedMessageView.actorLabel.text = ([message.actorDisplayName isEqualToString:@""]) ? NSLocalizedString(@"Guest", nil) : message.actorDisplayName;
    self.quotedMessageView.messageLabel.text = message.parsedMarkdownForChat.string;
    self.quotedMessageView.highlighted = [message isMessageFrom:userId];

    TalkAccount *account = message.account;
    if (account) {
        [self.quotedMessageView.avatarImageView setActorAvatarForMessage:message withAccount:account];
    }

    [self.cancelButton setHidden:NO];

    // Reset button size to 44 in case it was hidden before
    self.cancelButtonWidthConstraint.constant = 44;

    self.visible = YES;
}

- (void)hideCloseButton
{
    [self.cancelButton setHidden:YES];
    // With 2*4 padding (left and right to the button) we add 8 to have 16 as we have on the left side of the quoteView
    self.cancelButtonWidthConstraint.constant = 8;
}


@end
