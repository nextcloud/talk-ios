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

#import "FileMessageTableViewCell.h"

#import "MaterialActivityIndicator.h"
#import "SLKUIConstants.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCChatFileController.h"
#import "NCDatabaseManager.h"
#import "NCUtils.h"
#import "NCChatViewController.h"

@implementation FilePreviewImageView : UIImageView

@end

@interface FileMessageTableViewCell ()
{
    MDCActivityIndicator *_activityIndicator;
}

@end

@implementation FileMessageTableViewCell 

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
    
    _playIconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kFileMessageCellVideoPlayIconSize, kFileMessageCellVideoPlayIconSize)];
    _playIconImageView.hidden = YES;
    [_playIconImageView setTintColor:[UIColor colorWithWhite:1.0 alpha:0.8]];
    [_playIconImageView setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBlack]]];
    
    _previewImageView = [[FilePreviewImageView alloc] initWithFrame:CGRectMake(0, 0, kFileMessageCellFileMaxPreviewHeight, kFileMessageCellFileMaxPreviewHeight)];
    _previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewImageView.userInteractionEnabled = NO;
    _previewImageView.layer.cornerRadius = kFileMessageCellFilePreviewCornerRadius;
    _previewImageView.layer.masksToBounds = YES;
    [_previewImageView setImage:[UIImage imageNamed:@"file-chat-preview"]];
    [_previewImageView addSubview:_playIconImageView];
    [_previewImageView bringSubviewToFront:_playIconImageView];
    
    UITapGestureRecognizer *previewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)];
    [_previewImageView addGestureRecognizer:previewTap];
    _previewImageView.userInteractionEnabled = YES;
    
    if ([self.reuseIdentifier isEqualToString:FileMessageCellIdentifier]) {
        [self.contentView addSubview:_avatarView];
        [self.contentView addSubview:self.titleLabel];
        [self.contentView addSubview:self.dateLabel];
    }
    [self.contentView addSubview:_previewImageView];
    [self.contentView addSubview:self.bodyTextView];

    _statusStackView = [[UIStackView alloc] init];
    _statusStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _statusStackView.axis = UILayoutConstraintAxisVertical;
    _statusStackView.distribution = UIStackViewDistributionEqualSpacing;
    _statusStackView.alignment = UIStackViewAlignmentTop;
    [self.contentView addSubview:self.statusStackView];
    
    _statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _statusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusStackView addArrangedSubview:_statusView];
    
    _fileStatusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _fileStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusStackView addArrangedSubview:_fileStatusView];
    
    [self.contentView addSubview:self.reactionsView];
    
    _previewImageView.contentMode = UIViewContentModeScaleAspectFit;
    
    NSDictionary *views = @{@"avatarView": self.avatarView,
                            @"statusStackView": self.statusStackView,
                            @"titleLabel": self.titleLabel,
                            @"dateLabel": self.dateLabel,
                            @"previewImageView": self.previewImageView,
                            @"bodyTextView": self.bodyTextView,
                            @"reactionsView": self.reactionsView
                            };
    
    NSDictionary *metrics = @{@"avatarSize": @(kChatCellAvatarHeight),
                              @"dateLabelWidth": @(kChatCellDateLabelWidth),
                              @"previewSize": @(kFileMessageCellFileMaxPreviewHeight),
                              @"statusStackHeight" : @(kChatCellStatusViewHeight),
                              @"padding": @15,
                              @"avatarGap": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    if ([self.reuseIdentifier isEqualToString:FileMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[titleLabel]-[dateLabel(>=dateLabelWidth)]-right-|" options:0 metrics:metrics views:views]];
        self.hPreviewSize = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[previewImageView(previewSize)]-(>=0)-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.hPreviewSize];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[reactionsView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        self.vPreviewSize = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(avatarSize)]-left-[previewImageView(previewSize)]-right-[bodyTextView(>=0@999)]-0-[reactionsView(0)]-left-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.vPreviewSize];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarView(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(avatarSize)]-left-[statusStackView(statusStackHeight)]-(>=0)-|" options:0 metrics:metrics views:views]];
    } else if ([self.reuseIdentifier isEqualToString:GroupedFileMessageCellIdentifier]) {
        self.hGroupedPreviewSize = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[previewImageView(previewSize)]-(>=0)-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.hGroupedPreviewSize];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[reactionsView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        self.vGroupedPreviewSize = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[previewImageView(previewSize)]-right-[bodyTextView(>=0@999)]-0-[reactionsView(0)]-left-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.vGroupedPreviewSize];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[statusStackView(statusStackHeight)]-(>=0)-|" options:0 metrics:metrics views:views]];
    }
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusStackView(statusStackHeight)]-padding-[previewImageView(>=0)]-(>=0)-|" options:NSLayoutFormatAlignAllTop metrics:metrics views:views]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeIsDownloading:) name:NCChatFileControllerDidChangeIsDownloadingNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeDownloadProgress:) name:NCChatFileControllerDidChangeDownloadProgressNotification object:nil];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    CGFloat pointSize = [FileMessageTableViewCell defaultFontSize];
    
    self.titleLabel.font = [UIFont systemFontOfSize:pointSize];
    self.bodyTextView.font = [UIFont systemFontOfSize:pointSize];
    
    self.titleLabel.text = @"";
    self.bodyTextView.text = @"";
    self.dateLabel.text = @"";
    
    [self.avatarView cancelImageDownloadTask];
    self.avatarView.image = nil;
    
    [self.previewImageView cancelImageDownloadTask];
    self.previewImageView.layer.borderWidth = 0.0f;
    self.previewImageView.image = nil;
    self.playIconImageView.hidden = YES;
    
    self.vPreviewSize[3].constant = kFileMessageCellFileMaxPreviewHeight;
    self.hPreviewSize[3].constant = kFileMessageCellFileMaxPreviewHeight;
    self.vGroupedPreviewSize[1].constant = kFileMessageCellFileMaxPreviewHeight;
    self.hGroupedPreviewSize[1].constant = kFileMessageCellFileMaxPreviewHeight;
    
    self.vPreviewSize[7].constant = 0;
    self.vGroupedPreviewSize[5].constant = 0;
    
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    [self clearFileStatusView];
}

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead
{
    self.titleLabel.text = message.actorDisplayName;
    self.bodyTextView.attributedText = message.parsedMessageForChat;
    self.messageId = message.messageId;
    self.message = message;
    
    BOOL isMediaFile = [NCUtils isImageFileType:message.file.mimetype] || [NCUtils isVideoFileType:message.file.mimetype];
    BOOL isVideoFile = [NCUtils isVideoFileType:message.file.mimetype];
    
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
    self.dateLabel.text = [NCUtils getTimeFromDate:date];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId withStyle:self.traitCollection.userInterfaceStyle andSize:96 usingAccount:activeAccount]
                               placeholderImage:nil success:nil failure:nil];
    
    NSString *imageName = [[NCUtils previewImageForFileMIMEType:message.file.mimetype] stringByAppendingString:@"-chat-preview"];
    UIImage *filePreviewImage = [UIImage imageNamed:imageName];
    NSInteger requestedHeight = 3 * kFileMessageCellFileMaxPreviewHeight;
    __weak typeof(self) weakSelf = self;

    [self.previewImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createPreviewRequestForFile:message.file.parameterId withMaxHeight:requestedHeight usingAccount:activeAccount]
                                     placeholderImage:filePreviewImage success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
        
                                       //TODO: How to adjust for dark mode?
                                       weakSelf.previewImageView.layer.borderColor = [[UIColor secondarySystemFillColor] CGColor];
                                       weakSelf.previewImageView.layer.borderWidth = 1.0f;
                    
                                       dispatch_async(dispatch_get_main_queue(), ^(void){
                                           CGFloat width = image.size.width * image.scale;
                                           CGFloat height = image.size.height * image.scale;
                                           
                                           CGFloat previewMaxHeight = isMediaFile ? kFileMessageCellMediaFilePreviewHeight : kFileMessageCellFileMaxPreviewHeight;
                                           CGFloat previewMaxWidth = isMediaFile ? kFileMessageCellMediaFileMaxPreviewWidth : kFileMessageCellFileMaxPreviewWidth;
                                           
                                           if (height < kFileMessageCellMinimumHeight) {
                                               CGFloat ratio = kFileMessageCellMinimumHeight / height;
                                               width = width * ratio;
                                               if (width > previewMaxWidth) {
                                                   width = previewMaxWidth;
                                               }
                                               height = kFileMessageCellMinimumHeight;
                                           } else {
                                               if (height > previewMaxHeight) {
                                                   CGFloat ratio = previewMaxHeight / height;
                                                   width = width * ratio;
                                                   height = previewMaxHeight;
                                               }
                                               if (width > previewMaxWidth) {
                                                   CGFloat ratio = previewMaxWidth / width;
                                                   width = previewMaxWidth;
                                                   height = height * ratio;
                                               }
                                           }
                                           weakSelf.vPreviewSize[3].constant = height;
                                           weakSelf.hPreviewSize[3].constant = width;
                                           weakSelf.vGroupedPreviewSize[1].constant = height;
                                           weakSelf.hGroupedPreviewSize[1].constant = width;
                                           if (isVideoFile) {
                                               // only show the play icon if there is an image preview (not on top of the default video placeholder)
                                               weakSelf.playIconImageView.hidden = NO;
                                               // if the video preview is very narrow, make the play icon fit inside
                                               weakSelf.playIconImageView.frame = CGRectMake(0, 0, MIN(MIN(height, width), kFileMessageCellVideoPlayIconSize), MIN(MIN(height, width), kFileMessageCellVideoPlayIconSize));
                                               weakSelf.playIconImageView.center = CGPointMake(width / 2.0, height / 2.0);
                                           }
                                           [weakSelf.previewImageView setImage:image];
                                           [weakSelf setNeedsLayout];
                                           [weakSelf layoutIfNeeded];
                                           
                                           if (weakSelf.delegate) {
                                               [weakSelf.delegate cellHasDownloadedImagePreviewWithHeight:ceil(height) forMessage:message];
                                           }
                                       });
    } failure:nil];
    
    if (message.sendingFailed) {
        UIImageView *errorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [errorView setImage:[UIImage imageNamed:@"error"]];
        [self.statusView addSubview:errorView];
    } else if (message.isTemporary) {
        [self addActivityIndicator:0];
    } else if (message.file.fileStatus) {
        if (message.file.fileStatus.isDownloading && message.file.fileStatus.downloadProgress < 1) {
            [self addActivityIndicator:message.file.fileStatus.downloadProgress];
        }
    }
    
    self.fileParameter = message.file;
    
    if (message.file.contactPhotoImage) {
        [self.previewImageView setImage:message.file.contactPhotoImage];
    }
    
    [self.reactionsView updateReactionsWithReactions:message.reactionsArray];
    if (message.reactionsArray.count > 0) {
        _vPreviewSize[7].constant = 40;
        _vGroupedPreviewSize[5].constant = 40;
    }

    if ([message.actorId isEqualToString:activeAccount.userId]) {
        [self.statusView setHidden:NO];
    } else {
        [self.statusView setHidden:YES];
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

- (void)didChangeIsDownloading:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NCChatFileStatus *receivedStatus = [notification.userInfo objectForKey:@"fileStatus"];
        
        if (![receivedStatus.fileId isEqualToString:self->_fileParameter.parameterId] || ![receivedStatus.filePath isEqualToString:self->_fileParameter.path]) {
            // Received a notification for a different cell
            return;
        }
        
        BOOL isDownloading = [[notification.userInfo objectForKey:@"isDownloading"] boolValue];
        
        if (isDownloading && !self->_activityIndicator) {
            // Immediately show an indeterminate indicator as long as we don't have a progress value
            [self addActivityIndicator:0];
        } else if (!isDownloading && self->_activityIndicator) {
            [self clearFileStatusView];
        }
    });
}
- (void)didChangeDownloadProgress:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NCChatFileStatus *receivedStatus = [notification.userInfo objectForKey:@"fileStatus"];
        
        if (![receivedStatus.fileId isEqualToString:self->_fileParameter.parameterId] || ![receivedStatus.filePath isEqualToString:self->_fileParameter.path]) {
            // Received a notification for a different cell
            return;
        }
        
        double progress = [[notification.userInfo objectForKey:@"progress"] doubleValue];

        if (self->_activityIndicator) {
            // Switch to determinate-mode and show progress
            self->_activityIndicator.indicatorMode = MDCActivityIndicatorModeDeterminate;
            [self->_activityIndicator setProgress:progress animated:YES];
        } else {
            // Make sure we have an activity indicator added to this cell
            [self addActivityIndicator:progress];
        }
    });
}

- (void)addActivityIndicator:(CGFloat)progress
{
    [self clearFileStatusView];
    
    _activityIndicator = [[MDCActivityIndicator alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    _activityIndicator.radius = 7.0f;
    _activityIndicator.cycleColors = @[UIColor.lightGrayColor];
    
    if (progress > 0) {
        _activityIndicator.indicatorMode = MDCActivityIndicatorModeDeterminate;
        [_activityIndicator setProgress:progress animated:NO];
    }
    
    [_activityIndicator startAnimating];
    [self.fileStatusView addSubview:_activityIndicator];
}

#pragma mark - Gesture recognizers

- (void)avatarTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if (self.delegate && self.message) {
        [self.delegate cellWantsToDisplayOptionsForMessageActor:self.message];
    }
}

- (void)previewTapped:(UITapGestureRecognizer *)recognizer
{
    if (!self.fileParameter || !self.fileParameter.path || !self.fileParameter.link) {
        return;
    }
    
    if (self.delegate) {
        [self.delegate cellWantsToDownloadFile:self.fileParameter];
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
        _titleLabel.font = [UIFont systemFontOfSize:[FileMessageTableViewCell defaultFontSize]];
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

- (MessageBodyTextView *)bodyTextView
{
    if (!_bodyTextView) {
        _bodyTextView = [MessageBodyTextView new];
        _bodyTextView.font = [UIFont systemFontOfSize:[FileMessageTableViewCell defaultFontSize]];
        _bodyTextView.dataDetectorTypes = UIDataDetectorTypeNone;
    }
    return _bodyTextView;
}

- (void)setGuestAvatar:(NSString *)displayName
{
    UIColor *guestAvatarColor = [NCAppBranding placeholderColor];
    NSString *name = ([displayName isEqualToString:@""]) ? @"?" : displayName;
    [_avatarView setImageWithString:name color:guestAvatarColor circular:true];
}

- (void)clearFileStatusView {
    if (_activityIndicator) {
        [_activityIndicator stopAnimating];
        _activityIndicator = nil;
    }

    [self.fileStatusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
    //    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
    //    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}

@end
