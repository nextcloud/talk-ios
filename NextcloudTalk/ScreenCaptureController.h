// From https://github.com/react-native-webrtc/react-native-webrtc (MIT License)
// SPDX-FileCopyrightText: 2023 React-Native-WebRTC authors
// SPDX-License-Identifier: MIT

#import <Foundation/Foundation.h>
#import "CapturerEventsDelegate.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kRTCScreensharingSocketFD;
extern NSString *const kRTCAppGroupIdentifier;

@class ScreenCapturer;

@interface ScreenCaptureController : NSObject

@property(nonatomic, strong) id<CapturerEventsDelegate> eventsDelegate;

- (instancetype)initWithCapturer:(nonnull ScreenCapturer *)capturer;
- (void)startCapture;
- (void)stopCapture;

@end

NS_ASSUME_NONNULL_END
