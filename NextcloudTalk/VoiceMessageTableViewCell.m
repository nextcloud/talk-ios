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

#import "VoiceMessageTableViewCell.h"

#import "MaterialActivityIndicator.h"
#import "SLKUIConstants.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCChatFileController.h"
#import "NCDatabaseManager.h"
#import "NCUtils.h"

#define k_play_button_tag   99
#define k_pause_button_tag  98

@interface VoiceMessageTableViewCell ()
{
    MDCActivityIndicator *_activityIndicator;
    UIView *_audioPlayerView;
}

@end

@implementation VoiceMessageTableViewCell

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
    
    _audioPlayerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    _audioPlayerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_audioPlayerView setSemanticContentAttribute:UISemanticContentAttributeForceLeftToRight];
    
    if ([self.reuseIdentifier isEqualToString:VoiceMessageCellIdentifier]) {
        [self.contentView addSubview:_avatarView];
        [self.contentView addSubview:self.titleLabel];
        [self.contentView addSubview:self.dateLabel];
    }
    [self.contentView addSubview:self.bodyTextView];
    [self.contentView addSubview:_audioPlayerView];
    
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playPauseButton addTarget:self action:@selector(playPauseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self setPlayButton];
    [_audioPlayerView addSubview:self.playPauseButton];
    
    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    self.slider.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *sliderThumb = [[UIImage imageNamed:@"circle"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.slider setThumbImage:sliderThumb forState:UIControlStateNormal];
    [self.slider setEnabled:NO];
    [self.slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.slider setSemanticContentAttribute:UISemanticContentAttributeForceLeftToRight];
    [_audioPlayerView addSubview:self.slider];
    
    _statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _statusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_statusView];
    
    _fileStatusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _fileStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    [_audioPlayerView addSubview:_fileStatusView];
    
    _durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _durationLabel.font = [UIFont systemFontOfSize:12];
    _durationLabel.adjustsFontSizeToFitWidth = YES;
    _durationLabel.minimumScaleFactor = 0.5;
    [_audioPlayerView addSubview:_durationLabel];
    
    [self.contentView addSubview:self.reactionsView];
    
    NSDictionary *views = @{@"avatarView": self.avatarView,
                            @"statusView": self.statusView,
                            @"fileStatusView": self.fileStatusView,
                            @"durationLabel": self.durationLabel,
                            @"playButton" : self.playPauseButton,
                            @"progressView" : self.slider,
                            @"titleLabel": self.titleLabel,
                            @"dateLabel": self.dateLabel,
                            @"bodyTextView": self.bodyTextView,
                            @"audioPlayerView": _audioPlayerView,
                            @"reactionsView": self.reactionsView
                            };
    
    NSDictionary *metrics = @{@"avatarSize": @(kChatCellAvatarHeight),
                              @"dateLabelWidth": @(kChatCellDateLabelWidth),
                              @"statusSize": @(kChatCellStatusViewHeight),
                              @"statusTopPadding": @17,
                              @"buttonHeight": @44,
                              @"progressWidth": @150,
                              @"progressPadding": @20,
                              @"progressHeight": @4,
                              @"statusPadding": @12,
                              @"padding": @15,
                              @"avatarGap": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    if ([self.reuseIdentifier isEqualToString:VoiceMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[titleLabel]-[dateLabel(>=dateLabelWidth)]-right-|" options:0 metrics:metrics views:views]];
        self.vConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(avatarSize)]-left-[audioPlayerView(buttonHeight)]-right-[bodyTextView(>=0@999)]-0-[reactionsView(0)]-left-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.vConstraints];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(avatarSize)]-statusTopPadding-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarView(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    } else if ([self.reuseIdentifier isEqualToString:GroupedVoiceMessageCellIdentifier]) {
        self.vGroupedConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[audioPlayerView(buttonHeight)]-right-[bodyTextView(>=0@999)]-0-[reactionsView(0)]-left-|" options:0 metrics:metrics views:views];
        [self.contentView addConstraints:self.vGroupedConstraints];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-statusTopPadding-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    }
    
    [_audioPlayerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[playButton(buttonHeight)]-[progressView(progressWidth)]-[fileStatusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    [_audioPlayerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[playButton(buttonHeight)]-[progressView(progressWidth)]-[durationLabel(>=0)]-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[audioPlayerView(>=0)]-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[reactionsView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
    [_audioPlayerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[playButton(buttonHeight)]|" options:0 metrics:metrics views:views]];
    [_audioPlayerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-progressPadding-[progressView(progressHeight)]-progressPadding-|" options:0 metrics:metrics views:views]];
    [_audioPlayerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-statusPadding-[fileStatusView(statusSize)]-statusPadding-|" options:0 metrics:metrics views:views]];
    [_audioPlayerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-statusPadding-[durationLabel(statusSize)]-statusPadding-|" options:0 metrics:metrics views:views]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeIsDownloading:) name:NCChatFileControllerDidChangeIsDownloadingNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeDownloadProgress:) name:NCChatFileControllerDidChangeDownloadProgressNotification object:nil];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    CGFloat pointSize = [VoiceMessageTableViewCell defaultFontSize];
    
    self.titleLabel.font = [UIFont systemFontOfSize:pointSize];
    self.bodyTextView.font = [UIFont systemFontOfSize:pointSize];
    
    self.titleLabel.text = @"";
    self.bodyTextView.text = @"";
    self.dateLabel.text = @"";
    
    [self.avatarView cancelImageDownloadTask];
    self.avatarView.image = nil;
    
    self.vConstraints[7].constant = 0;
    self.vGroupedConstraints[5].constant = 0;
    
    [self resetPlayer];
    
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    [self clearFileStatusView];
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
    } else if (message.isTemporary) {
        [self addActivityIndicator:0];
    } else if (message.file.fileStatus) {
        if (message.file.fileStatus.isDownloading && message.file.fileStatus.downloadProgress < 1) {
            [self addActivityIndicator:message.file.fileStatus.downloadProgress];
        }
    }
    
    self.fileParameter = message.file;
    
    [self.reactionsView updateReactionsWithReactions:message.reactionsArray];
    if (message.reactionsArray.count > 0) {
        _vConstraints[7].constant = 40;
        _vGroupedConstraints[5].constant = 40;
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

- (void)setPlayerProgress:(CGFloat)progress isPlaying:(BOOL)playing maximumValue:(CGFloat)maxValue
{
    [self setPauseButton];
    if (!playing) {
        [self setPlayButton];
    }
    [self.slider setEnabled:YES];
    [self.slider setValue:progress];
    [self.slider setMaximumValue:maxValue];
    [self setDurationLabelWithProgress:progress andDuration:maxValue];
    [self.slider setNeedsLayout];
}
- (void)resetPlayer
{
    [self setPlayButton];
    [self.slider setEnabled:NO];
    [self.slider setValue:0];
    [self.durationLabel setHidden:YES];
    [self.slider setNeedsLayout];
}

- (void)setPlayButton
{
    UIImage *image = [[UIImage imageNamed:@"play"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.playPauseButton setImage:image forState:UIControlStateNormal];
    self.playPauseButton.tag = k_play_button_tag;
}

- (void)setPauseButton
{
    UIImage *image = [[UIImage imageNamed:@"pause"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.playPauseButton setImage:image forState:UIControlStateNormal];
    self.playPauseButton.tag = k_pause_button_tag;
}

- (void)sliderValueChanged:(id)sender
{
    if (self.delegate) {
        [self.delegate cellWantsToChangeProgress:_slider.value fromAudioFile:_fileParameter];
    }
}

- (void)setDurationLabelWithProgress:(CGFloat)progress andDuration:(CGFloat)duration
{
    NSDateComponentsFormatter *dateComponentsFormatter = [[NSDateComponentsFormatter alloc] init];
    dateComponentsFormatter.allowedUnits = (NSCalendarUnitMinute | NSCalendarUnitSecond);
    dateComponentsFormatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorNone;
    NSString *progressTime = [dateComponentsFormatter stringFromTimeInterval:progress];
    NSString *durationTime = [dateComponentsFormatter stringFromTimeInterval:duration];
    
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:12],
                                 NSForegroundColorAttributeName:[UIColor secondaryLabelColor]};
    NSDictionary *subAttribute = @{NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightMedium],
                                   NSForegroundColorAttributeName:[UIColor labelColor]};
    
    NSString *playerTime = [NSString stringWithFormat:@"%@ / %@", progressTime, durationTime];
    NSMutableAttributedString *playerTimeString = [[NSMutableAttributedString alloc] initWithString:playerTime attributes:attributes];
    [playerTimeString addAttributes:subAttribute range:NSMakeRange(0, [progressTime length])];
    
    self.durationLabel.attributedText = playerTimeString;
    [self.durationLabel setHidden:NO];
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
        _titleLabel.font = [UIFont systemFontOfSize:[VoiceMessageTableViewCell defaultFontSize]];
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
        _bodyTextView.font = [UIFont systemFontOfSize:[VoiceMessageTableViewCell defaultFontSize]];
        _bodyTextView.dataDetectorTypes = UIDataDetectorTypeNone;
    }
    return _bodyTextView;
}

- (void)playPauseButtonTapped:(id)sender
{
    if (!self.fileParameter || !self.fileParameter.path || !self.fileParameter.link) {
        return;
    }
    
    if (self.delegate) {
        UIButton *buttton = sender;
        if (buttton.tag == k_play_button_tag) {
            [self.delegate cellWantsToPlayAudioFile:self.fileParameter];
        } else if (buttton.tag == k_pause_button_tag) {
            [self.delegate cellWantsToPauseAudioFile:self.fileParameter];
        }
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
