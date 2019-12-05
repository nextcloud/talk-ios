//
//  QuotedMessageView.m
//  VideoCalls
//
//  Created by Ivan Sein on 25.11.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "QuotedMessageView.h"

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
    self.backgroundColor = [UIColor colorWithRed:247.0/255.0 green:247.0/255.0 blue:247.0/255.0 alpha:1.0]; //Default toolbar color
        
    [self addSubview:self.quoteView];
    [self addSubview:self.actorLabel];
    [self addSubview:self.messageLabel];
    
    NSDictionary *views = @{@"quoteView": self.quoteView,
                            @"actorLabel": self.actorLabel,
                            @"messageLabel": self.messageLabel
                            };
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quoteView(4)]-[actorLabel]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quoteView(4)]-[messageLabel]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[quoteView(50)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-5-[actorLabel(18)]-4-[messageLabel(18)]-5-|" options:0 metrics:nil views:views]];
}


#pragma mark - Getters

- (UIView *)quoteView
{
    if (!_quoteView) {
        _quoteView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, 50)];
        _quoteView.translatesAutoresizingMaskIntoConstraints = NO;
        _quoteView.backgroundColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1]; //#0082C9
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


@end
