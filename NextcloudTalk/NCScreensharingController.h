/**
 * SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@class RTCVideoSource;
@class RTCVideoCapturer;

NS_ASSUME_NONNULL_BEGIN

@interface NCScreensharingController : NSObject

- (void)startCaptureWithVideoSource:(RTCVideoSource *)videoSource withVideoCapturer:(RTCVideoCapturer *)capturer;
- (void)stopCapture;

@end

NS_ASSUME_NONNULL_END
