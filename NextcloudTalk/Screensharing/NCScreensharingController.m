/**
 * SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCScreensharingController.h"

#import <WebRTC/RTCVideoSource.h>

#import "ScreenCapturer.h"
#import "ScreenCaptureController.h"

@interface NCScreensharingController () <RTCVideoCapturerDelegate>
{
    ScreenCapturer *_screenCapturer;
    ScreenCaptureController *_screenCapturerController;
    RTCVideoSource *_videoSource;
    RTCVideoCapturer *_videoCapturer;
}

@end

@implementation NCScreensharingController

- (void)startCaptureWithVideoSource:(RTCVideoSource *)videoSource withVideoCapturer:(RTCVideoCapturer *)capturer
{
    _videoSource = videoSource;
    _videoCapturer = capturer;

    _screenCapturer = [[ScreenCapturer alloc] initWithDelegate:self];
    _screenCapturerController = [[ScreenCaptureController alloc] initWithCapturer:_screenCapturer];
    [_screenCapturerController startCapture];
}

- (void)stopCapture
{
    if (_screenCapturerController) {
        [_screenCapturerController stopCapture];
        _screenCapturerController = nil;
        _screenCapturer = nil;
    }
}

- (void)capturer:(RTCVideoCapturer *)capturer didCaptureVideoFrame:(RTCVideoFrame *)frame
{
    if (_videoSource && _videoCapturer) {
        [_videoSource capturer:_videoCapturer didCaptureVideoFrame:frame];
    }
}

@end
