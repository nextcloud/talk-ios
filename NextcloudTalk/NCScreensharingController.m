/**
 * @copyright Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
 *
 * @author Marcel Müller <marcel-mueller@gmx.de>
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
