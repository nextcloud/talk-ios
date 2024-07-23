// From https://github.com/react-native-webrtc/react-native-webrtc (MIT License)
// SPDX-FileCopyrightText: 2023 React-Native-WebRTC authors
// SPDX-License-Identifier: MIT

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SocketConnection : NSObject

- (instancetype)initWithFilePath:(nonnull NSString *)filePath;
- (void)openWithStreamDelegate:(id<NSStreamDelegate>)streamDelegate;
- (void)close;

@end

NS_ASSUME_NONNULL_END
