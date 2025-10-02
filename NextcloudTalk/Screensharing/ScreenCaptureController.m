// From https://github.com/react-native-webrtc/react-native-webrtc (MIT License)
// SPDX-FileCopyrightText: 2023 React-Native-WebRTC authors
// SPDX-License-Identifier: MIT

#include <sys/socket.h>
#include <sys/un.h>

#import "ScreenCaptureController.h"
#import "ScreenCapturer.h"
#import "SocketConnection.h"

#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

NSString *const kRTCScreensharingSocketFD = @"rtc_SSFD";

@interface ScreenCaptureController ()

@property(nonatomic, retain) ScreenCapturer *capturer;

@end

@interface ScreenCaptureController (CapturerEventsDelegate)<CapturerEventsDelegate>
- (void)capturerDidEnd:(RTCVideoCapturer *)capturer;
@end

@interface ScreenCaptureController (Private)

@property(nonatomic, readonly) NSString *appGroupIdentifier;

@end

@implementation ScreenCaptureController

- (instancetype)initWithCapturer:(nonnull ScreenCapturer *)capturer {
    self = [super init];
    if (self) {
        self.capturer = capturer;
    }

    return self;
}

- (void)dealloc {
    [self.capturer stopCapture];
}

- (void)startCapture {
    self.capturer.eventsDelegate = self;
    NSString *socketFilePath = [self filePathForApplicationGroupIdentifier:groupIdentifier];
    SocketConnection *connection = [[SocketConnection alloc] initWithFilePath:socketFilePath];
    [self.capturer startCaptureWithConnection:connection];
}

- (void)stopCapture {
    [self.capturer stopCapture];
}

// MARK: CapturerEventsDelegate Methods

- (void)capturerDidEnd:(RTCVideoCapturer *)capturer {
    [self.eventsDelegate capturerDidEnd:capturer];
}

// MARK: Private Methods

- (NSString *)filePathForApplicationGroupIdentifier:(nonnull NSString *)identifier {
    NSURL *sharedContainer =
        [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:identifier];
    NSString *socketFilePath = [[sharedContainer URLByAppendingPathComponent:kRTCScreensharingSocketFD] path];

    return socketFilePath;
}

@end

