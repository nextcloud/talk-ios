/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "CallParticipantViewCell.h"

#import "NCAPIController.h"
#import "NCDatabaseManager.h"

#import "NextcloudTalk-Swift.h"

NSString *const kCallParticipantCellIdentifier = @"CallParticipantCellIdentifier";
NSString *const kCallParticipantCellNibName = @"CallParticipantViewCell";
CGFloat const kCallParticipantCellMinHeight = 128;

@interface CallParticipantViewCell()
{
    UIView<RTCVideoRenderer> *_videoView;
    CGSize _remoteVideoSize;
    NSTimer *_disconnectedTimer;
}

@end

@implementation CallParticipantViewCell

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    self.audioOffIndicator.hidden = YES;
    self.screensharingIndicator.hidden = YES;
    self.raisedHandIndicator.hidden = YES;
    
    self.audioOffIndicator.layer.cornerRadius = 4;
    self.audioOffIndicator.clipsToBounds = YES;
    self.screensharingIndicator.layer.cornerRadius = 4;
    self.screensharingIndicator.clipsToBounds = YES;

    self.activityIndicator.radius = 50.0f;
    self.activityIndicator.cycleColors = @[UIColor.lightGrayColor];

    self.peerAvatarImageView.hidden = YES;
    self.peerAvatarImageView.layer.cornerRadius = self.peerAvatarImageView.bounds.size.width / 2;
    self.peerAvatarImageView.layer.masksToBounds = YES;

    self.layer.cornerRadius = 22.0f;
    [self.layer setMasksToBounds:YES];
    
    _showOriginalSize = NO;
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleZoom)];
    [tapGestureRecognizer setNumberOfTapsRequired:2];
    [self.contentView addGestureRecognizer:tapGestureRecognizer];
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    [_peerAvatarImageView cancelCurrentRequest];
    _peerAvatarImageView.image = nil;
    _peerAvatarImageView.alpha = 1;

    _displayName = nil;
    _peerNameLabel.text = nil;
    [_videoView removeFromSuperview];
    _videoView = nil;
    _showOriginalSize = NO;
    self.layer.borderWidth = 0.0f;
    [self hideLoadingSpinner];
    [self invalidateDisconnectedTimer];
}

- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes
{
    [super applyLayoutAttributes:layoutAttributes];
    
    [self resizeRemoteVideoView];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGRect bounds = self.bounds;

    // Usually we have a padding to the side of the cell of 22 (= cornerRadius)
    // But when the cell is really small adjust the padding to be 11 (= cornerRadius / 2)
    if (bounds.size.width <= 200 || bounds.size.height <= 200) {
        self.stackViewLeftConstraint.constant = 11;
        self.stackViewRightConstraint.constant = 11;
        self.stackViewBottomConstraint.constant = 11;
        self.screensharingIndiciatorTopConstraint.constant = 11;
        self.screensharingIndiciatorRightConstraint.constant = 11;
    } else {
        self.stackViewLeftConstraint.constant = 22;
        self.stackViewRightConstraint.constant = 22;
        self.stackViewBottomConstraint.constant = 22;
        self.screensharingIndiciatorTopConstraint.constant = 22;
        self.screensharingIndiciatorRightConstraint.constant = 22;
    }

    [self.contentView layoutSubviews];

    self.peerAvatarImageView.layer.cornerRadius = self.peerAvatarImageView.bounds.size.width / 2;
    self.activityIndicator.radius = self.peerAvatarImageView.bounds.size.width / 2;
}

- (void)toggleZoom
{
    _showOriginalSize = !_showOriginalSize;
    [self.actionsDelegate cellWantsToChangeZoom:self showOriginalSize:_showOriginalSize];
    [self resizeRemoteVideoView];
}

- (void)setAvatarForActor:(TalkActor * _Nullable)actor
{
    if (actor.id == nil || actor.id.length == 0) {
        [self setBackgroundColor:[UIColor colorWithWhite:0.5 alpha:1]];
    } else if (actor.displayName && actor.displayName.length > 0) {
        [self setBackgroundColor:[[ColorGenerator shared] usernameToColor:actor.displayName]];
    } else {
        [self setBackgroundColor:[[ColorGenerator shared] usernameToColor:actor.id]];
    }

    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self.peerAvatarImageView setActorAvatarForId:actor.id withType:actor.type withDisplayName:actor.displayName withRoomToken:nil using:activeAccount];
}

- (void)setDisplayName:(NSString *)displayName
{
    _displayName = displayName;
    if (!displayName || [displayName isKindOfClass:[NSNull class]] || [displayName isEqualToString:@""]) {
        _displayName = NSLocalizedString(@"Guest", nil);
    }

    if ([self.peerNameLabel.text isEqualToString:_displayName]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerNameLabel.text = self->_displayName;
        [self setBackgroundColor:[[ColorGenerator shared] usernameToColor:self->_displayName]];
    });
}

- (void)setAudioDisabled:(BOOL)audioDisabled
{
    _audioDisabled = audioDisabled;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self configureParticipantButtons];
    });
}

- (void)setScreenShared:(BOOL)screenShared
{
    _screenShared = screenShared;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self configureParticipantButtons];
    });
}

- (void)setConnectionState:(RTCIceConnectionState)connectionState
{
    _connectionState = connectionState;

    [self invalidateDisconnectedTimer];
    if (connectionState == RTCIceConnectionStateDisconnected) {
        [self setDisconnectedTimer];
    } else if (connectionState == RTCIceConnectionStateFailed) {
        [self setFailedConnectionUI];
    } else if (connectionState != RTCIceConnectionStateCompleted && connectionState != RTCIceConnectionStateConnected) {
        [self setConnectingUI];
    } else {
        [self setConnectedUI];
    }
}

- (void)setDisconnectedTimer
{
    _disconnectedTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(setDisconnectedUI) userInfo:nil repeats:NO];
}

- (void)invalidateDisconnectedTimer
{
    [_disconnectedTimer invalidate];
    _disconnectedTimer = nil;
}

- (void)setDisconnectedUI
{
    if (_connectionState == RTCIceConnectionStateDisconnected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.peerNameLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Connecting to %@ …", nil), self->_displayName];
            self.peerAvatarImageView.alpha = 0.3;
            [self hideLoadingSpinner];
        });
    }
}

- (void)setConnectingUI
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerAvatarImageView.alpha = 0.3;
        [self showLoadingSpinner];
    });
}

- (void)setFailedConnectionUI
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerNameLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Failed to connect to %@", nil), self->_displayName];
        self.peerAvatarImageView.alpha = 0.3;
    });
}

- (void)setConnectedUI
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerNameLabel.text = self->_displayName;
        self.peerAvatarImageView.alpha = 1;
        [self hideLoadingSpinner];
    });
}

- (void)showLoadingSpinner
{
    [self.activityIndicator startAnimating];
    [self.activityIndicator setHidden:NO];
}

- (void)hideLoadingSpinner
{
    [self.activityIndicator stopAnimating];
    [self.activityIndicator setHidden:YES];
}

- (IBAction)screenSharingButtonPressed:(id)sender
{
    [self.actionsDelegate cellWantsToPresentScreenSharing:self];
}

- (void)configureParticipantButtons
{    
    self.audioOffIndicator.hidden = !_audioDisabled;
    self.screensharingIndicator.hidden = !_screenShared;
}

- (void)setVideoDisabled:(BOOL)videoDisabled
{
    _videoDisabled = videoDisabled;
    if (videoDisabled) {
        [_videoView setHidden:YES];
        [_peerAvatarImageView setHidden:NO];
    } else {
        [_peerAvatarImageView setHidden:YES];
        [_videoView setHidden:NO];
    }
}

- (void)setSpeaking:(BOOL)speaking
{
    if (speaking) {
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.layer.borderWidth = 2.0f;
    } else {
        self.layer.borderWidth = 0.0f;
    }
}

- (void)setRaiseHand:(BOOL)raised
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.raisedHandIndicator.hidden = !raised;
    });
}

- (void)setVideoView:(RTCMTLVideoView *)videoView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (videoView == self->_videoView) {
            return;
        }

        [self->_videoView removeFromSuperview];
        self->_videoView = nil;
        self->_videoView = videoView;
        [self->_peerVideoView addSubview:self->_videoView];
        [self->_videoView setHidden:self->_videoDisabled];
        [self resizeRemoteVideoView];
    });
}

- (CGSize)getRemoteVideoSize
{
    return self->_remoteVideoSize;
}

- (void)setRemoteVideoSize:(CGSize)size
{
    self->_remoteVideoSize = size;
    [self resizeRemoteVideoView];
}

- (void)resizeRemoteVideoView
{
    CGRect bounds = self.bounds;
    CGSize videoSize = _remoteVideoSize;
    
    if (videoSize.width > 0 && videoSize.height > 0) {
        // Aspect fill remote video into bounds.
        CGRect remoteVideoFrame = AVMakeRectWithAspectRatioInsideRect(videoSize, bounds);
        CGFloat scale = 1;
        
        if (!_showOriginalSize) {
            CGFloat scaleHeight = bounds.size.height / remoteVideoFrame.size.height;
            CGFloat scaleWidth = bounds.size.width / remoteVideoFrame.size.width;
            // Always grab the bigger scale to make video cover the whole cell
            scale = (scaleHeight > scaleWidth) ? scaleHeight : scaleWidth;
        }
        
        remoteVideoFrame.size.height *= scale;
        remoteVideoFrame.size.width *= scale;
        _videoView.frame = remoteVideoFrame;
        _videoView.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    } else {
        _videoView.frame = bounds;
    }
}

@end
