//
//  ReplyMessageView.m
//  VideoCalls
//
//  Created by Ivan Sein on 21.11.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "ReplyMessageView.h"
#import "SLKUIConstants.h"
#import "NCChatMessage.h"
#import "QuotedMessageView.h"

@interface ReplyMessageView ()
@property (nonatomic, strong) UIView *quoteContainerView;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) CALayer *topBorder;
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
    self.backgroundColor = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0]; //Default toolbar color
    
    [self addSubview:self.quoteContainerView];
    [self addSubview:self.cancelButton];
    [self.layer addSublayer:self.topBorder];
    
    [_quoteContainerView addSubview:self.quotedMessageView];
    
    NSDictionary *views = @{@"quoteContainerView": self.quoteContainerView,
                            @"quotedMessageView": self.quotedMessageView,
                            @"cancelButton": self.cancelButton
                            };
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quoteContainerView]-[cancelButton(44)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quotedMessageView(quoteContainerView)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[quoteContainerView(50)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[cancelButton(50)]|" options:0 metrics:nil views:views]];
}

#pragma mark - UIView

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    self.topBorder.frame = CGRectMake(0, 0, self.bounds.size.width, 0.5);
}


#pragma mark - SLKTypingIndicatorProtocol

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
        _quoteContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
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
        [_cancelButton setImage:[UIImage imageNamed:@"cancel"] forState:UIControlStateNormal];
        [_cancelButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    }
    return _cancelButton;
}

- (CALayer *)topBorder
{
    if (!_topBorder) {
        _topBorder = [CAGradientLayer layer];
        _topBorder.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(SLKKeyWindowBounds()), 0.5);
        _topBorder.backgroundColor = [UIColor lightGrayColor].CGColor;
    }
    return _topBorder;
}


#pragma mark - ReplyMessageView

- (void)presentReplyViewWithMessage:(NCChatMessage *)message
{
    if (self.isVisible || !message) {
        return;
    }
    
    self.message = message;
    self.quotedMessageView.actorLabel.text = message.actorDisplayName;
    self.quotedMessageView.messageLabel.text = message.parsedMessage.string;
    
    self.visible = YES;
}


@end
