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

#import "DBImageColorPicker.h"
#import "CallViewController.h"
#import "NCAPIController.h"
#import "NCUtils.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"

NSString *const kCallParticipantCellIdentifier = @"CallParticipantCellIdentifier";
NSString *const kCallParticipantCellNibName = @"CallParticipantViewCell";

@interface CallParticipantViewCell()
{
    UIView<RTCVideoRenderer> *_videoView;
    CGSize _remoteVideoSize;
    BOOL _showOriginalSize;
    AvatarBackgroundImageView *_backgroundImageView;
    NSTimer *_disconnectedTimer;
}

@end

@implementation CallParticipantViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.audioOffIndicator.hidden = YES;
    self.screensharingIndicator.hidden = YES;
    self.peerAvatarImageView.hidden = YES;
    self.peerAvatarImageView.layer.cornerRadius = 64;
    self.peerAvatarImageView.layer.masksToBounds = YES;
    
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
    _backgroundImageView = nil;
    _peerNameLabel.text = nil;
    [_videoView removeFromSuperview];
    _videoView = nil;
    _showOriginalSize = NO;
    self.layer.borderWidth = 0.0f;
}

- (void)toggleZoom
{
    _showOriginalSize = !_showOriginalSize;
    [self resizeRemoteVideoView];
}

- (void)setUserAvatar:(NSString *)userId
{
    if (!_backgroundImageView) {
        _backgroundImageView = [[AvatarBackgroundImageView alloc] initWithFrame:self.bounds];
        __weak UIImageView *weakBGView = _backgroundImageView;
        self.backgroundView = _backgroundImageView;
        [_backgroundImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:userId andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                    placeholderImage:nil success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
                                        NSDictionary *headers = [response allHeaderFields];
                                        id customAvatarHeader = [headers objectForKey:@"X-NC-IsCustomAvatar"];
                                        BOOL shouldShowBlurBackground = YES;
                                        if (customAvatarHeader) {
                                            shouldShowBlurBackground = [customAvatarHeader boolValue];
                                        } else if ([response statusCode] == 201) {
                                            shouldShowBlurBackground = NO;
                                        }
                                        
                                        if (shouldShowBlurBackground) {
                                            UIImage *blurImage = [NCUtils blurImageFromImage:image];
                                            [weakBGView setImage:blurImage];
                                            weakBGView.contentMode = UIViewContentModeScaleAspectFill;
                                        } else {
                                            DBImageColorPicker *colorPicker = [[DBImageColorPicker alloc] initFromImage:image withBackgroundType:DBImageColorPickerBackgroundTypeDefault];
                                            [weakBGView setBackgroundColor:colorPicker.backgroundColor];
                                            weakBGView.backgroundColor = [weakBGView.backgroundColor colorWithAlphaComponent:0.8];
                                        }
                                    } failure:nil];
        
        if (!userId || userId.length == 0) {
            weakBGView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1];
        }
    }
    
    if (userId && userId.length > 0) {
        [self.peerAvatarImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:userId andSize:256 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
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
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerNameLabel.text = _displayName;
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
            self.peerNameLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Connecting to %@ …", nil), _displayName];
            self.peerAvatarImageView.alpha = 0.3;
        });
    }
}

- (void)setFailedConnectionUI
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerNameLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Failed to connect to %@", nil), _displayName];
        self.peerAvatarImageView.alpha = 0.3;
    });
}

- (void)setConnectedUI
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerNameLabel.text = _displayName;
        self.peerAvatarImageView.alpha = 1;
    });
}

- (IBAction)screenSharingButtonPressed:(id)sender
{
    [self.actionsDelegate cellWantsToPresentScreenSharing:self];
}

- (void)configureParticipantButtons
{
    CGRect audioDisabledFrame = _audioOffIndicator.frame;
    CGRect screenSharedFrame = _screensharingIndicator.frame;
    
    audioDisabledFrame.origin.x = (_screenShared) ? 0 : 26;
    screenSharedFrame.origin.x = (_audioDisabled) ? 52 : 26;
    
    self.audioOffIndicator.frame = audioDisabledFrame;
    self.screensharingIndicator.frame = screenSharedFrame;
    
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

- (void)setVideoView:(RTCEAGLVideoView *)videoView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_videoView removeFromSuperview];
        _videoView = nil;
        _videoView = videoView;
        _remoteVideoSize = videoView.frame.size;
        [_peerVideoView addSubview:_videoView];
        [_videoView setHidden:_videoDisabled];
        [self resizeRemoteVideoView];
    });
}

- (void)resizeRemoteVideoView {
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
