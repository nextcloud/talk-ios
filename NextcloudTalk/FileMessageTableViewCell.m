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
    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kFileMessageCellAvatarHeight, kFileMessageCellAvatarHeight)];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.userInteractionEnabled = NO;
    _avatarView.backgroundColor = [NCAppBranding placeholderColor];
    _avatarView.layer.cornerRadius = kFileMessageCellAvatarHeight/2.0;
    _avatarView.layer.masksToBounds = YES;
    
    _previewImageView = [[FilePreviewImageView alloc] initWithFrame:CGRectMake(0, 0, kFileMessageCellFilePreviewHeight, kFileMessageCellFilePreviewHeight)];
    _previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewImageView.userInteractionEnabled = NO;
    _previewImageView.layer.cornerRadius = 4.0;
    _previewImageView.layer.masksToBounds = YES;
    [_previewImageView setImage:[UIImage imageNamed:@"file-chat-preview"]];
    
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
    
    _statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _statusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_statusView];
    
    _fileStatusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _fileStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_fileStatusView];
    
    NSDictionary *views = @{@"avatarView": self.avatarView,
                            @"statusView": self.statusView,
                            @"fileStatusView": self.fileStatusView,
                            @"titleLabel": self.titleLabel,
                            @"dateLabel": self.dateLabel,
                            @"previewImageView": self.previewImageView,
                            @"bodyTextView": self.bodyTextView,
                            };
    
    NSDictionary *metrics = @{@"avatarSize": @(kFileMessageCellAvatarHeight),
                              @"previewSize": @(kFileMessageCellFilePreviewHeight),
                              @"statusSize": @(kChatCellStatusViewHeight),
                              @"padding": @15,
                              @"avatarGap": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    if ([self.reuseIdentifier isEqualToString:FileMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[titleLabel]-[dateLabel(40)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[previewImageView(previewSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[fileStatusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(28)]-left-[previewImageView(previewSize)]-right-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(28)]-left-[previewImageView(previewSize)]-right-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarView(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(28)]-left-[fileStatusView(previewSize)]-right-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    } else if ([self.reuseIdentifier isEqualToString:GroupedFileMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[previewImageView(previewSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[fileStatusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[previewImageView(previewSize)]-right-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[fileStatusView(previewSize)]-right-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    }
    
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
    
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    [self clearFileStatusView];
}

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead
{
    self.titleLabel.text = message.actorDisplayName;
    self.bodyTextView.attributedText = message.parsedMessage;
    self.messageId = message.messageId;
    
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
    self.dateLabel.text = [NCUtils getTimeFromDate:date];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96 usingAccount:activeAccount]
                               placeholderImage:nil success:nil failure:nil];
   
    NSString *imageName = [[NCUtils previewImageForFileMIMEType:message.file.mimetype] stringByAppendingString:@"-chat-preview"];
    UIImage *filePreviewImage = [UIImage imageNamed:imageName];
    __weak FilePreviewImageView *weakPreviewImageView = self.previewImageView;
    [self.previewImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createPreviewRequestForFile:message.file.parameterId width:120 height:120 usingAccount:activeAccount]
                                     placeholderImage:filePreviewImage success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
                                         [weakPreviewImageView setImage:image];
                                         //TODO: How to adjust for dark mode?
                                         weakPreviewImageView.layer.borderColor = [[UIColor colorWithWhite:0.9 alpha:1.0] CGColor];
                                         if (@available(iOS 13.0, *)) {
                                             weakPreviewImageView.layer.borderColor = [[UIColor secondarySystemFillColor] CGColor];
                                         }
                                         weakPreviewImageView.layer.borderWidth = 1.0f;
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
    
    if (message.file.contactName) {
        self.bodyTextView.text = message.file.contactName;
    }
    if (message.file.contactPhotoImage) {
        [self.previewImageView setImage:message.file.contactPhotoImage];
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


#pragma mark - Getters

- (UILabel *)titleLabel
{
    if (!_titleLabel) {
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.userInteractionEnabled = NO;
        _titleLabel.numberOfLines = 0;
        _titleLabel.textColor = [UIColor lightGrayColor];
        _titleLabel.font = [UIFont systemFontOfSize:[FileMessageTableViewCell defaultFontSize]];
        
        if (@available(iOS 13.0, *)) {
            _titleLabel.textColor = [UIColor secondaryLabelColor];
        }
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
        _dateLabel.numberOfLines = 0;
        _dateLabel.textColor = [UIColor lightGrayColor];
        _dateLabel.font = [UIFont systemFontOfSize:12.0];
        
        if (@available(iOS 13.0, *)) {
            _dateLabel.textColor = [UIColor secondaryLabelColor];
        }
    }
    return _dateLabel;
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

- (void)previewTapped:(UITapGestureRecognizer *)recognizer
{
    if (!self.fileParameter || !self.fileParameter.path || !self.fileParameter.link) {
        return;
    }
    
    if (self.delegate) {
        [self.delegate cellWantsToDownloadFile:self.fileParameter];
    }
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
