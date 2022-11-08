/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

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
    self.backgroundColor = [UIColor secondarySystemBackgroundColor];
    
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
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[quoteContainerView]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[cancelButton]|" options:0 metrics:nil views:views]];
}

#pragma mark - UIView

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    self.topBorder.frame = CGRectMake(0, 0, self.bounds.size.width, 0.5);
}

- (CGSize)intrinsicContentSize
{
    // This will indicate the size of the view when calling systemLayoutSizeFittingSize in SLKTextViewController
    return CGSizeMake(UIViewNoIntrinsicMetric, 50);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    if (_topBorder && [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        // We use a CGColor so we loose the automatic color changing of dynamic colors -> update manually
        _topBorder.backgroundColor = [UIColor systemGray4Color].CGColor;
    }
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
        _topBorder.backgroundColor = [UIColor systemGray4Color].CGColor;
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
    self.quotedMessageView.messageLabel.text = message.parsedMessageForChat.string;
    self.quotedMessageView.highlighted = [message isMessageFromUser:userId];
    
    self.visible = YES;
}


@end
