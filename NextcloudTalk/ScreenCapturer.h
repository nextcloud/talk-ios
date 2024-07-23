// From https://github.com/react-native-webrtc/react-native-webrtc (MIT License)
// SPDX-FileCopyrightText: 2023 React-Native-WebRTC authors
// SPDX-License-Identifier: MIT

#import <AVFoundation/AVFoundation.h>
#import <WebRTC/RTCVideoCapturer.h>
#import "CapturerEventsDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class SocketConnection;

@interface ScreenCapturer : RTCVideoCapturer

@property(nonatomic, weak) id<CapturerEventsDelegate> eventsDelegate;

- (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate;
- (void)startCaptureWithConnection:(nonnull SocketConnection *)connection;
- (void)stopCapture;

@end

NS_ASSUME_NONNULL_END
