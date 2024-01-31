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

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCChatFileController.h"
#import "NCDatabaseManager.h"

#import "NextcloudTalk-Swift.h"

@implementation FilePreviewImageView : UIImageView

@end

@interface FileMessageTableViewCell ()
{
    MDCActivityIndicator *_activityIndicator;
    MDCActivityIndicator *_previewActivityIndicator;
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
    _avatarButton = [[AvatarButton alloc] initWithFrame:CGRectMake(0, 0, kChatCellAvatarHeight, kChatCellAvatarHeight)];
    _avatarButton.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarButton.backgroundColor = [NCAppBranding placeholderColor];
    _avatarButton.layer.cornerRadius = kChatCellAvatarHeight/2.0;
    _avatarButton.layer.masksToBounds = YES;
    _avatarButton.showsMenuAsPrimaryAction = YES;
    _avatarButton.imageView.contentMode = UIViewContentModeScaleToFill;

    _playIconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kFileMessageCellVideoPlayIconSize, kFileMessageCellVideoPlayIconSize)];
    _playIconImageView.hidden = YES;
    [_playIconImageView setTintColor:[UIColor colorWithWhite:1.0 alpha:0.8]];
    [_playIconImageView setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBlack]]];
    
    _previewImageView = [[FilePreviewImageView alloc] initWithFrame:CGRectMake(0, 0, kFileMessageCellFileMaxPreviewHeight, kFileMessageCellFileMaxPreviewHeight)];
    _previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewImageView.userInteractionEnabled = NO;
    _previewImageView.layer.cornerRadius = kFileMessageCellFilePreviewCornerRadius;
    _previewImageView.layer.masksToBounds = YES;
    [_previewImageView addSubview:_playIconImageView];
    [_previewImageView bringSubviewToFront:_playIconImageView];
    
    UITapGestureRecognizer *previewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)];
    [_previewImageView addGestureRecognizer:previewTap];
    _previewImageView.userInteractionEnabled = YES;

    _previewActivityIndicator = [[MDCActivityIndicator alloc] initWithFrame:CGRectMake(0, 0, kFileMessageCellMinimumHeight, kFileMessageCellMinimumHeight)];
    _previewActivityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _previewActivityIndicator.radius = kFileMessageCellMinimumHeight / 2;
    _previewActivityIndicator.cycleColors = @[UIColor.lightGrayColor];
    _previewActivityIndicator.indicatorMode = MDCActivityIndicatorModeIndeterminate;

    if ([self.reuseIdentifier isEqualToString:FileMessageCellIdentifier]) {
        [self.contentView addSubview:self.avatarButton];
        [self.contentView addSubview:self.titleLabel];
        [self.contentView addSubview:self.dateLabel];
    }

    [self.contentView addSubview:self.bodyTextView];
    [self.contentView addSubview:_previewImageView];
    [_previewImageView addSubview:_previewActivityIndicator];

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
    
    NSDictionary *views = @{@"avatarButton": self.avatarButton,
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
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarButton(avatarSize)]-right-[titleLabel]-[dateLabel(>=dateLabelWidth)]-right-|" options:0 metrics:metrics views:views]];
        self.hPreviewSize = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarButton(avatarSize)]-right-[previewImageView(previewSize)]-(>=0)-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.hPreviewSize];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarButton(avatarSize)]-right-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarButton(avatarSize)]-right-[reactionsView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        self.vPreviewSize = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(avatarSize)]-left-[previewImageView(previewSize)]-right-[bodyTextView(>=0@999)]-0-[reactionsView(0)]-left-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.vPreviewSize];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarButton(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
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

    [NSLayoutConstraint activateConstraints:@[[_previewActivityIndicator.centerYAnchor constraintEqualToAnchor:_previewImageView.centerYAnchor]]];
    [NSLayoutConstraint activateConstraints:@[[_previewActivityIndicator.centerXAnchor constraintEqualToAnchor:_previewImageView.centerXAnchor]]];

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
    
    [self.avatarButton cancelCurrentRequest];
    [self.avatarButton setImage:nil forState:UIControlStateNormal];
    
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

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        // We use a CGColor so we loose the automatic color changing of dynamic colors -> update manually
        self.previewImageView.layer.borderColor = [[UIColor secondarySystemFillColor] CGColor];
    }
}

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];

    if (message.lastEditActorDisplayName || message.lastEditTimestamp > 0) {
        NSString *editedString;

        if ([message.lastEditActorId isEqualToString:message.actorId] && [message.lastEditActorType isEqualToString:@"users"]) {
            editedString = NSLocalizedString(@"edited", "A message was edited");
            editedString = [NSString stringWithFormat:@" (%@)", editedString];
        } else {
            editedString = NSLocalizedString(@"edited by", "A message was edited by ...");
            editedString = [NSString stringWithFormat:@" (%@ %@)", editedString, message.lastEditActorDisplayName];
        }

        NSMutableAttributedString *editedAttributedString = [[NSMutableAttributedString alloc] initWithString:editedString];
        NSRange rangeEditedString = NSMakeRange(0, [editedAttributedString length]);
        [editedAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:14] range:rangeEditedString];
        [editedAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor tertiaryLabelColor] range:rangeEditedString];

        NSMutableAttributedString *actorDisplayNameString = [[NSMutableAttributedString alloc] initWithString:message.actorDisplayName];
        [actorDisplayNameString appendAttributedString:editedAttributedString];

        self.titleLabel.attributedText = actorDisplayNameString;
    } else {
        self.titleLabel.text = message.actorDisplayName;
    }

    self.bodyTextView.attributedText = message.parsedMarkdownForChat;
    self.messageId = message.messageId;
    self.message = message;

    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
    self.dateLabel.text = [NCUtils getTimeFromDate:date];
    
    [self.avatarButton setUserAvatarFor:message.actorId with:self.traitCollection.userInterfaceStyle using:activeAccount];

    _avatarButton.menu = [super getDeferredUserMenuForMessage:message];

    [self requestPreviewForMessage:message withAccount:activeAccount];
    
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

    if (self.message.isReplyable && !self.message.isDeleting) {
        __weak typeof(self) weakSelf = self;
        [self addReplyGestureWithActionBlock:^(UITableView *tableView, NSIndexPath *indexPath) {
            __strong typeof(self) strongSelf = weakSelf;
            [strongSelf.delegate cellWantsToReplyToMessage:strongSelf.message];
        }];
    }
}

- (void)requestPreviewForMessage:(NCChatMessage *)message withAccount:(TalkAccount *)account
{
    if (!message.file.previewAvailable) {
        // Don't request a preview if we know that there's none
        NSString *imageName = [[NCUtils previewImageForMimeType:message.file.mimetype] stringByAppendingString:@"-chat-preview"];
        [self.previewImageView setImage:[UIImage imageNamed:imageName]];

        [_previewActivityIndicator setHidden:YES];
        [_previewActivityIndicator stopAnimating];

        return;
    }

    BOOL isVideoFile = [NCUtils isVideoWithFileType:message.file.mimetype];
    BOOL isMediaFile = isVideoFile || [NCUtils isImageWithFileType:message.file.mimetype];

    NSInteger requestedHeight = 3 * kFileMessageCellFileMaxPreviewHeight;
    __weak typeof(self) weakSelf = self;

    // In case we can determine the height before requesting the preview, adjust the imageView constraints accordingly
    if (message.file.previewImageHeight > 0) {
        self.vPreviewSize[3].constant = message.file.previewImageHeight;
        self.vGroupedPreviewSize[1].constant = message.file.previewImageHeight;
    } else {
        CGFloat estimatedPreviewHeight = [FileMessageTableViewCell getEstimatedPreviewImageHeightForMessage:message];

        if (estimatedPreviewHeight > 0) {
            self.vPreviewSize[3].constant = estimatedPreviewHeight;
            self.vGroupedPreviewSize[1].constant = estimatedPreviewHeight;
        }
    }

    [_previewActivityIndicator setHidden:NO];
    [_previewActivityIndicator startAnimating];

    [self.previewImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createPreviewRequestForFile:message.file.parameterId withMaxHeight:requestedHeight usingAccount:account]
                                     placeholderImage:nil success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {

                                       __strong typeof(self) strongSelf = weakSelf;

                                       if (strongSelf) {
                                           [strongSelf->_previewActivityIndicator setHidden:YES];
                                           [strongSelf->_previewActivityIndicator stopAnimating];
                                       }

                                       weakSelf.previewImageView.layer.borderColor = [[UIColor secondarySystemFillColor] CGColor];
                                       weakSelf.previewImageView.layer.borderWidth = 1.0f;

                                       CGSize imageSize = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
                                       CGSize previewSize = [FileMessageTableViewCell getPreviewSizeFromImageSize:imageSize isMediaFile:isMediaFile];

                                       weakSelf.vPreviewSize[3].constant = previewSize.height;
                                       weakSelf.hPreviewSize[3].constant = previewSize.width;
                                       weakSelf.vGroupedPreviewSize[1].constant = previewSize.height;
                                       weakSelf.hGroupedPreviewSize[1].constant = previewSize.width;

                                       if (isVideoFile) {
                                           // only show the play icon if there is an image preview (not on top of the default video placeholder)
                                           weakSelf.playIconImageView.hidden = NO;
                                           // if the video preview is very narrow, make the play icon fit inside
                                           weakSelf.playIconImageView.frame = CGRectMake(0, 0, MIN(MIN(previewSize.height, previewSize.width), kFileMessageCellVideoPlayIconSize), MIN(MIN(previewSize.height, previewSize.width), kFileMessageCellVideoPlayIconSize));
                                           weakSelf.playIconImageView.center = CGPointMake(previewSize.width / 2.0, previewSize.height / 2.0);
                                       }
        
                                       [weakSelf.previewImageView setImage:image];

                                       if (weakSelf.delegate) {
                                           [weakSelf.delegate cellHasDownloadedImagePreviewWithHeight:ceil(previewSize.height) forMessage:message];
                                       }
    } failure:nil];
}

+ (CGSize)getPreviewSizeFromImageSize:(CGSize)imageSize isMediaFile:(BOOL)isMediaFile {
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;

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

    return CGSizeMake(width, height);
}

+ (CGFloat)getEstimatedPreviewImageHeightForMessage:(NCChatMessage *)message
{
    if (!message || !message.file) {
        return 0;
    }

    NCMessageFileParameter *fileParameter = message.file;

    // We don't have any information about the image to display
    if (fileParameter.width == 0 && fileParameter.height == 0) {
        return 0;
    }

    // We can only estimate the height for images and videos
    if (![NCUtils isVideoWithFileType:fileParameter.mimetype] && ![NCUtils isImageWithFileType:fileParameter.mimetype]) {
        return 0;
    }

    CGSize imageSize = CGSizeMake(fileParameter.width, fileParameter.height);
    CGSize previewSize = [self getPreviewSizeFromImageSize:imageSize isMediaFile:YES];

    return ceil(previewSize.height);
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
