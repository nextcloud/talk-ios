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

#import "QuotedMessageView.h"

#import "NCAppBranding.h"

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
    self.backgroundColor = [UIColor secondarySystemBackgroundColor];

    [self addSubview:self.quoteView];
    [self addSubview:self.actorLabel];
    [self addSubview:self.messageLabel];
    
    NSDictionary *views = @{@"quoteView": self.quoteView,
                            @"actorLabel": self.actorLabel,
                            @"messageLabel": self.messageLabel
                            };
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quoteView(4)]-[actorLabel]-|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[quoteView(4)]-[messageLabel]-|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[quoteView(50)]|" options:0 metrics:nil views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-5-[actorLabel(18)]-4-[messageLabel(18)]-5-|" options:0 metrics:nil views:views]];
}


#pragma mark - Getters

- (UIView *)quoteView
{
    if (!_quoteView) {
        _quoteView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, 50)];
        _quoteView.translatesAutoresizingMaskIntoConstraints = NO;
        _quoteView.backgroundColor = [UIColor systemFillColor];
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
        
        _messageLabel.font = [UIFont systemFontOfSize:14.0];
        _messageLabel.textColor = [NCAppBranding chatForegroundColor];
    }
    return _messageLabel;
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
