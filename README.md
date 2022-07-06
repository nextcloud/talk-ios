# Nextcloud Talk iOS app

**Video & audio calls and chat through Nextcloud on iOS**

Nextcloud Talk is a fully on-premises audio/video and chat communication service. It features web and mobile apps and is designed to offer the highest degree of security while being easy to use.

Nextcloud Talk lowers the barrier for communication and lets your team connect any time, any where, on any device, with each other, customers or partners.

[![Available on the AppStore](https://github.com/nextcloud/talk-ios/blob/master/docs/App%20Store/Download_on_the_App_Store_Badge.svg)](https://itunes.apple.com/app/id1296825574)

## Prerequisites

- [Nextcloud server](https://github.com/nextcloud/server) version 14 or higher (that fulfills [ATS requirements](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW57)).
- [Nextcloud Talk](https://github.com/nextcloud/spreed) version 4.0 or higher.
- [CocoaPods](https://cocoapods.org/)

## Development setup

```
$ pod install

$ git submodule update --init

$ open NextcloudTalk.xcworkspace
```

Pull Requests will be checked with [SwiftLint](https://github.com/realm/SwiftLint). We strongly encourage the installation of SwiftLint to detect issues as early as possible.

## WebRTC library

We are using our own builds of the WebRTC library. They can be found in this [repository](https://github.com/nextcloud-releases/talk-clients-webrtc)
Current version: [96.4664.0](https://github.com/nextcloud-releases/talk-clients-webrtc/releases/tag/96.4664.0-RC1)

## Push notifications

If you are experiencing problems with push notifications, please check this [document](https://github.com/nextcloud/talk-ios/blob/master/docs/notifications.md) to detect possible issues.

## TestFlight

Do you want to try the latest version in development of Nextcloud Talk iOS? Simple, follow this simple step

[Apple TestFlight](https://testflight.apple.com/join/cxzyr1eO)

We are also available on [our public Talk team conversation](https://cloud.nextcloud.com/call/c7fz9qpr), if you want to join the discussion.

**License:** [GPLv3](https://github.com/nextcloud/spreed-ios/blob/master/LICENSE) with [Apple app store exception](https://github.com/nextcloud/spreed-ios/blob/master/COPYING.iOS).

