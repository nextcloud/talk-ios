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

#import "CallParticipantViewCell.h"

#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"

#import "CallViewController.h"
#import "NCAPIController.h"
#import "NCDatabaseManager.h"
#import "NCUtils.h"

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
    _displayName = nil;
    _peerAvatarImageView.alpha = 1;
    _peerNameLabel.text = nil;
    [_videoView removeFromSuperview];
    _videoView = nil;
    _showOriginalSize = NO;
    self.layer.borderWidth = 0.0f;
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
}

- (void)toggleZoom
{
    _showOriginalSize = !_showOriginalSize;
    [self.actionsDelegate cellWantsToChangeZoom:self showOriginalSize:_showOriginalSize];
    [self resizeRemoteVideoView];
}

- (void)setUserAvatar:(NSString *)userId withDisplayName:(NSString *)displayName
{
    if (!userId || userId.length == 0) {
        [self setBackgroundColor:[UIColor colorWithWhite:0.5 alpha:1]];
    } else if (displayName.length > 0) {
        [self setBackgroundColor:[[ColorGenerator shared] usernameToColor:displayName]];
    } else {
        [self setBackgroundColor:[[ColorGenerator shared] usernameToColor:userId]];
    }
    
    if (userId && userId.length > 0) {
        [self.peerAvatarImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:userId withStyle:self.traitCollection.userInterfaceStyle andSize:256 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                        placeholderImage:nil success:nil failure:nil];
    } else {
        UIColor *guestAvatarColor = [UIColor colorWithRed:0.73 green:0.73 blue:0.73 alpha:1.0]; /*#b9b9b9*/
        [self.peerAvatarImageView setImageWithString:@"?" color:guestAvatarColor circular:true];
    }
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
        });
    }
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
    });
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
