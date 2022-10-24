/**
 * @copyright Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
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

#import "ObjectShareMessageTableViewCell.h"

#import "MaterialActivityIndicator.h"
#import "SLKUIConstants.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCUtils.h"

@implementation ObjectShareMessageTableViewCell

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
    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kChatCellAvatarHeight, kChatCellAvatarHeight)];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.userInteractionEnabled = YES;
    _avatarView.backgroundColor = [NCAppBranding placeholderColor];
    _avatarView.layer.cornerRadius = kChatCellAvatarHeight/2.0;
    _avatarView.layer.masksToBounds = YES;
    UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped:)];
    [_avatarView addGestureRecognizer:avatarTap];
    
    _objectContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    _objectContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    _objectContainerView.layer.cornerRadius = 8.0;
    _objectContainerView.layer.masksToBounds = YES;
    _objectContainerView.layer.borderWidth = 1.0;
    _objectContainerView.layer.borderColor = [NCAppBranding placeholderColor].CGColor;
    
    _objectTypeImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kObjectShareMessageCellObjectTypeImageSize, kObjectShareMessageCellObjectTypeImageSize)];
    _objectTypeImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _objectTypeImageView.userInteractionEnabled = NO;
    _objectTypeImageView.layer.cornerRadius = 4.0;
    _objectTypeImageView.layer.masksToBounds = YES;
    [_objectContainerView addSubview:_objectTypeImageView];
    
    _objectTitle = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];
    _objectTitle.translatesAutoresizingMaskIntoConstraints = NO;
    _objectTitle.textContainer.lineFragmentPadding = 0;
    _objectTitle.textContainerInset = UIEdgeInsetsZero;
    _objectTitle.backgroundColor = [UIColor clearColor];
    _objectTitle.editable = NO;
    _objectTitle.scrollEnabled = NO;
    _objectTitle.userInteractionEnabled = NO;
    _objectTitle.font = [UIFont systemFontOfSize:[ObjectShareMessageTableViewCell defaultFontSize]];
    [_objectContainerView addSubview:_objectTitle];
    
    UITapGestureRecognizer *previewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(objectTapped:)];
    [_objectContainerView addGestureRecognizer:previewTap];
    _objectContainerView.userInteractionEnabled = YES;
    
    if ([self.reuseIdentifier isEqualToString:ObjectShareMessageCellIdentifier]) {
        [self.contentView addSubview:_avatarView];
        [self.contentView addSubview:self.titleLabel];
        [self.contentView addSubview:self.dateLabel];
    }
    [self.contentView addSubview:_objectContainerView];
    
    _statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _statusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_statusView];
    
    [self.contentView addSubview:self.reactionsView];
    
    NSDictionary *views = @{@"avatarView": self.avatarView,
                            @"statusView": self.statusView,
                            @"objectContainerView": self.objectContainerView,
                            @"objectTypeImageView": self.objectTypeImageView,
                            @"objectTitle" : self.objectTitle,
                            @"titleLabel": self.titleLabel,
                            @"dateLabel": self.dateLabel,
                            @"reactionsView": self.reactionsView
                            };
    
    NSDictionary *metrics = @{@"avatarSize": @(kChatCellAvatarHeight),
                              @"dateLabelWidth": @(kChatCellDateLabelWidth),
                              @"statusSize": @(kChatCellStatusViewHeight),
                              @"objectTypeImageSize": @(kObjectShareMessageCellObjectTypeImageSize),
                              @"statusTopPadding": @17,
                              @"statusPadding": @12,
                              @"padding": @15,
                              @"avatarGap": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    if ([self.reuseIdentifier isEqualToString:ObjectShareMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[titleLabel]-[dateLabel(>=dateLabelWidth)]-right-|" options:0 metrics:metrics views:views]];
        self.vConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(avatarSize)]-left-[objectContainerView(>=0@999)]-0-[reactionsView(0)]-left-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.vConstraints];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(avatarSize)]-statusTopPadding-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarView(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    } else if ([self.reuseIdentifier isEqualToString:GroupedObjectShareMessageCellIdentifier]) {
        self.vGroupedConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[objectContainerView(>=0@999)]-0-[reactionsView(0)]-left-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.vGroupedConstraints];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-statusTopPadding-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    }
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[objectContainerView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[reactionsView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusView(statusSize)]-padding-[objectContainerView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [_objectContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[objectTypeImageView(objectTypeImageSize)]-right-[objectTitle(>=0)]-left-|" options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
    [_objectContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(>=0)-[objectTypeImageView(objectTypeImageSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    [_objectContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[objectTitle(>=0)]-right-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    CGFloat pointSize = [ObjectShareMessageTableViewCell defaultFontSize];
    
    self.titleLabel.font = [UIFont systemFontOfSize:pointSize];
    
    self.titleLabel.text = @"";
    self.dateLabel.text = @"";
    
    [self.avatarView cancelImageDownloadTask];
    self.avatarView.image = nil;
    
    self.objectTypeImageView.image = nil;
    self.objectTitle.text = @"";
    
    self.vConstraints[5].constant = 0;
    self.vGroupedConstraints[3].constant = 0;
    
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
}

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead
{
    self.titleLabel.text = message.actorDisplayName;
    self.messageId = message.messageId;
    self.message = message;
    
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
    self.dateLabel.text = [NCUtils getTimeFromDate:date];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:activeAccount]
                               placeholderImage:nil success:nil failure:nil];
   
    
    if (message.sendingFailed) {
        UIImageView *errorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [errorView setImage:[UIImage imageNamed:@"error"]];
        [self.statusView addSubview:errorView];
    }
    
    self.objectParameter = message.objectShareParameter;
    self.objectTitle.text = self.objectParameter.name;
    
    if (message.poll) {
        [self.objectTypeImageView setImage:[[UIImage imageNamed:@"poll"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        [self.objectTypeImageView setTintColor:[UIColor labelColor]];
    }
    
    [self.reactionsView updateReactionsWithReactions:message.reactionsArray];
    if (message.reactionsArray.count > 0) {
        _vConstraints[5].constant = 40;
        _vGroupedConstraints[3].constant = 40;
    }
    
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    BOOL shouldShowDeliveryStatus = [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadStatus forAccountId:activeAccount.accountId];
    BOOL shouldShowReadStatus = !serverCapabilities.readStatusPrivacy;
    if ([message.actorId isEqualToString:activeAccount.userId] && [message.actorType isEqualToString:@"users"] && shouldShowDeliveryStatus) {
        if (lastCommonRead >= message.messageId && shouldShowReadStatus) {
            [self setDeliveryState:ChatMessageDeliveryStateRead];
        } else {
            [self setDeliveryState:ChatMessageDeliveryStateSent];
        }
    }
}

- (void)setDeliveryState:(ChatMessageDeliveryState)state
{
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    
    if (state == ChatMessageDeliveryStateSent) {
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

#pragma mark - Gesture recognizers

- (void)avatarTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if (self.delegate && self.message) {
        [self.delegate cellWantsToDisplayOptionsForMessageActor:self.message];
    }
}

- (void)objectTapped:(UITapGestureRecognizer *)recognizer
{
    if (!self.objectParameter) {
        return;
    }
    
    if (self.delegate && self.message.poll) {
        [self.delegate cellWantsToOpenPoll:self.objectParameter];
    }
}

#pragma mark - ReactionsView delegate

- (void)didSelectReactionWithReaction:(NCChatReaction *)reaction
{
    [self.delegate cellDidSelectedReaction:reaction forMessage:self.message];
}

#pragma mark - Getters

- (UILabel *)titleLabel
{
    if (!_titleLabel) {
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.userInteractionEnabled = NO;
        _titleLabel.numberOfLines = 1;
        _titleLabel.font = [UIFont systemFontOfSize:[ObjectShareMessageTableViewCell defaultFontSize]];
        _titleLabel.textColor = [UIColor secondaryLabelColor];
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
        _dateLabel.numberOfLines = 1;
        _dateLabel.font = [UIFont systemFontOfSize:12.0];
        _dateLabel.textColor = [UIColor secondaryLabelColor];
    }
    return _dateLabel;
}

- (ReactionsView *)reactionsView
{
    if (!_reactionsView) {
        UICollectionViewFlowLayout *flowLayout = [[UICollectionViewFlowLayout alloc] init];
        flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        _reactionsView = [[ReactionsView alloc] initWithFrame:CGRectMake(0, 0, 50, 50) collectionViewLayout:flowLayout];
        _reactionsView.translatesAutoresizingMaskIntoConstraints = NO;
        _reactionsView.reactionsDelegate = self;
    }
    return _reactionsView;
}

- (void)setGuestAvatar:(NSString *)displayName
{
    UIColor *guestAvatarColor = [NCAppBranding placeholderColor];
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

@end
