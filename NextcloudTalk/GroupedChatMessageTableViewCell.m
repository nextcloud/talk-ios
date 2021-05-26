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

#import "GroupedChatMessageTableViewCell.h"
#import "MaterialActivityIndicator.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "SLKUIConstants.h"
#import "NCAppBranding.h"

@implementation GroupedChatMessageTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [NCAppBranding backgroundColor];
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    [self.contentView addSubview:self.bodyTextView];
    
    _statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _statusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_statusView];
    
    NSDictionary *views = @{@"bodyTextView": self.bodyTextView,
                            @"statusView": self.statusView
                            };
    
    NSDictionary *metrics = @{@"avatar": @50,
                              @"statusSize": @(kChatCellStatusViewHeight),
                              @"padding": @15,
                              @"right": @10,
                              @"left": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatar-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    CGFloat pointSize = [GroupedChatMessageTableViewCell defaultFontSize];
    
    self.bodyTextView.font = [UIFont systemFontOfSize:pointSize];
    
    self.bodyTextView.text = @"";
    
    self.statusView.hidden = NO;
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
}

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead
{
    self.bodyTextView.attributedText = message.parsedMessage;
    self.messageId = message.messageId;
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    BOOL shouldShowDeliveryStatus = [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadStatus forAccountId:activeAccount.accountId];
    BOOL shouldShowReadStatus = !serverCapabilities.readStatusPrivacy;
    
    if (message.isDeleting) {
        [self setDeliveryState:ChatMessageDeliveryStateDeleting];
    } else if (message.sendingFailed) {
        [self setDeliveryState:ChatMessageDeliveryStateFailed];
    } else if (message.isTemporary){
        [self setDeliveryState:ChatMessageDeliveryStateSending];
    } else if ([message.actorId isEqualToString:activeAccount.userId] && [message.actorType isEqualToString:@"users"] && shouldShowDeliveryStatus) {
        if (lastCommonRead >= message.messageId && shouldShowReadStatus) {
            [self setDeliveryState:ChatMessageDeliveryStateRead];
        } else {
            [self setDeliveryState:ChatMessageDeliveryStateSent];
        }
    }
    
    if ([message.messageType isEqualToString:kMessageTypeCommentDeleted]) {
        self.statusView.hidden = YES;
        self.bodyTextView.textColor = [UIColor colorWithWhite:0 alpha:0.3];
        if (@available(iOS 13.0, *)) {
            self.bodyTextView.textColor = [UIColor tertiaryLabelColor];
        }
    }
}

- (void)setDeliveryState:(ChatMessageDeliveryState)state
{
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    
    if (state == ChatMessageDeliveryStateSending || state == ChatMessageDeliveryStateDeleting) {
        MDCActivityIndicator *activityIndicator = [[MDCActivityIndicator alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        activityIndicator.radius = 7.0f;
        activityIndicator.cycleColors = @[UIColor.lightGrayColor];
        [activityIndicator startAnimating];
        [self.statusView addSubview:activityIndicator];
    } else if (state == ChatMessageDeliveryStateFailed) {
        UIImageView *errorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [errorView setImage:[UIImage imageNamed:@"error"]];
        [self.statusView addSubview:errorView];
    } else if (state == ChatMessageDeliveryStateSent) {
        UIImageView *checkView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [checkView setImage:[UIImage imageNamed:@"check"]];
        checkView.image = [checkView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [checkView setTintColor:[UIColor lightGrayColor]];
        [self.statusView addSubview:checkView];
    } else if (state == ChatMessageDeliveryStateRead) {
        UIImageView *checkAllView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [checkAllView setImage:[UIImage imageNamed:@"check-all"]];
        checkAllView.image = [checkAllView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [checkAllView setTintColor:[UIColor lightGrayColor]];
        [self.statusView addSubview:checkAllView];
    }
}

#pragma mark - Getters

- (MessageBodyTextView *)bodyTextView
{
    if (!_bodyTextView) {
        _bodyTextView = [MessageBodyTextView new];
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
