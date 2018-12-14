//
//  CallParticipantViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 06.10.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "CallParticipantViewCell.h"

#import <WebRTC/RTCAVFoundationVideoSource.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import "DBImageColorPicker.h"
#import "CallViewController.h"
#import "NCAPIController.h"
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
}

@end

@implementation CallParticipantViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.audioOffIndicator.hidden = YES;
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
    _backgroundImageView = nil;
    _peerNameLabel.text = nil;
    [_videoView removeFromSuperview];
    _videoView = nil;
    _showOriginalSize = NO;
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
        [_backgroundImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:userId andSize:256]
                                    placeholderImage:nil success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull image) {
                                        if ([response statusCode] == 200) {
                                            CIContext *context = [CIContext contextWithOptions:nil];
                                            CIImage *inputImage = [[CIImage alloc] initWithImage:image];
                                            CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
                                            [filter setValue:inputImage forKey:kCIInputImageKey];
                                            [filter setValue:[NSNumber numberWithFloat:8.0f] forKey:@"inputRadius"];
                                            CIImage *result = [filter valueForKey:kCIOutputImageKey];
                                            CGImageRef cgImage = [context createCGImage:result fromRect:[inputImage extent]];
                                            UIImage *finalImage = [UIImage imageWithCGImage:cgImage];
                                            [weakBGView setImage:finalImage];
                                            weakBGView.contentMode = UIViewContentModeScaleAspectFill;
                                        } else if ([response statusCode] == 201) {
                                            DBImageColorPicker *colorPicker = [[DBImageColorPicker alloc] initFromImage:image withBackgroundType:DBImageColorPickerBackgroundTypeDefault];
                                            [weakBGView setBackgroundColor:colorPicker.backgroundColor];
                                            weakBGView.backgroundColor = [weakBGView.backgroundColor colorWithAlphaComponent:0.8];
                                        }
                                    } failure:nil];
        
        if (!userId || userId.length == 0) {
            UIImage *avatarImage = [UIImage imageNamed:@"group-bg"];
            DBImageColorPicker *colorPicker = [[DBImageColorPicker alloc] initFromImage:avatarImage withBackgroundType:DBImageColorPickerBackgroundTypeDefault];
            [weakBGView setBackgroundColor:colorPicker.backgroundColor];
            weakBGView.backgroundColor = [weakBGView.backgroundColor colorWithAlphaComponent:0.8];
        }
    }
    
    if (userId && userId.length > 0) {
        [self.peerAvatarImageView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:userId andSize:256]
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
        _displayName = @"Guest";
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peerNameLabel.text = _displayName;
    });
}

- (void)setAudioDisabled:(BOOL)audioDisabled
{
    _audioDisabled = audioDisabled;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.audioOffIndicator.hidden = !_audioDisabled;
    });
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
