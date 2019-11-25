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

@interface ReplyMessageView ()
@property (nonatomic, strong) UIView *quoteView;
@property (nonatomic, strong) UILabel *actorLabel;
@property (nonatomic, strong) UILabel *messageLabel;
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
    self.quoteView.backgroundColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1]; //#0082C9
    
    [self addSubview:self.quoteView];
    [self addSubview:self.actorLabel];
    [self addSubview:self.messageLabel];
    [self addSubview:self.cancelButton];
    [self.layer addSublayer:self.topBorder];
    
    NSDictionary *views = @{@"quoteView": self.quoteView,
                            @"actorLabel": self.actorLabel,
                            @"messageLabel": self.messageLabel,
                            @"cancelButton": self.cancelButton
                            };
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quoteView(4)]-[actorLabel]-(>=0)-[cancelButton(44)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quoteView(4)]-[messageLabel]-(>=0)-[cancelButton(44)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[quoteView(50)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[cancelButton(50)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-5-[actorLabel(18)]-4-[messageLabel(18)]-5-|" options:0 metrics:nil views:views]];
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

- (UIView *)quoteView
{
    if (!_quoteView) {
        _quoteView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, 50)];
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
        
        _actorLabel.font = [UIFont systemFontOfSize:14.0];
        _actorLabel.textColor = [UIColor lightGrayColor];
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
        _messageLabel.numberOfLines = 1;
        _messageLabel.contentMode = UIViewContentModeLeft;
        
        _messageLabel.font = [UIFont systemFontOfSize:14.0];
        _messageLabel.textColor = [UIColor darkGrayColor];
    }
    return _messageLabel;
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
    
    self.actorLabel.text = message.actorDisplayName;
    self.messageLabel.text = message.parsedMessage.string;
    
    self.visible = YES;
}


@end
