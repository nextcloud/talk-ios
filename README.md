<!--
  - SPDX-FileCopyrightText: 2017 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: GPL-3.0-or-later
-->
# Nextcloud Talk iOS app

**Video & audio calls and chat through Nextcloud on iOS**

Nextcloud Talk is a fully on-premises audio/video and chat communication service. It features web and mobile apps and is designed to offer the highest degree of security while being easy to use.

Nextcloud Talk lowers the barrier for communication and lets your team connect any time, any where, on any device, with each other, customers or partners.

[![Available on the AppStore](https://github.com/nextcloud/talk-ios/blob/main/docs/App%20Store/Download_on_the_App_Store_Badge.svg)](https://itunes.apple.com/app/id1296825574)

## Prerequisites

- [Nextcloud server](https://github.com/nextcloud/server) version 14 or higher (that fulfills [ATS requirements](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW57)).
- [Nextcloud Talk](https://github.com/nextcloud/spreed) version 4.0 or higher.
- [CocoaPods](https://cocoapods.org/)

## Development setup
After cloning this repository, you can use `pod install` to install all dependencies. After that, open the project with `open NextcloudTalk.xcworkspace`.

Pull Requests will be checked with [SwiftLint](https://github.com/realm/SwiftLint). We strongly encourage the installation of SwiftLint to detect issues as early as possible.

## Run the project

Depending on how you try to run the project, you'll notice that it's not running "as-is". There are a few steps to make it work with your developer account:

1. The project contains multiple targets (currently `NextcloudTalk`, `ShareExtension` and `NotificationServiceExtension`). The bundle ids of those targets start with `com.nextcloud.Talk` which can't be used outside of Nextcloud GmbH. To run the project, change all bundle ids to something that's allowed for your developer account: `com.<yourname>.Talk`.
2. To communicate between the main app and its extensions, app groups are used. The group identifier for NextcloudTalk is set to `group.com.nextcloud.Talk`, with the same restriction as above. Change the group identifier of all targets to `group.com.<yourname>.Talk`.
3. Open the file `NCAppBranding.m` (can be found in XCode under NextcloudTalk -> Settings) and change `bundleIdentifier` and `groupIdentifier` to the same values you used in 1. and 2.
4. Run the project

## Contributing to Source Code

Thanks for wanting to contribute source code to the Talk iOS app. That's great! 🎉

Please read the [Code of Conduct](https://nextcloud.com/community/code-of-conduct/). This document offers some guidance to ensure Nextcloud participants can cooperate effectively in a positive and inspiring atmosphere, and to explain how together we can strengthen and support each other.

For more information please review the [guidelines for contributing](https://github.com/nextcloud/server/blob/main/.github/CONTRIBUTING.md) to this repository.

## How to contribute

1. 🐛 [Pick a good first issue](https://github.com/nextcloud/talk-ios/labels/good%20first%20issue) or any issue/feature you like to work on
2. 👩‍🔧 Create a branch and make your changes. Remember to sign off your commits using `git commit -sm "Your commit message"`
3. ⬆ Create a [pull request](https://opensource.guide/how-to-contribute/#opening-a-pull-request) and `@mention` the people from the issue to review
4. 👍 Fix things that come up during a review
5. 🎉 Wait for it to get merged!

You got stuck while working on a issue or need some pointers? Feel free to ask in the corresponding issue or in [our public Talk team conversation](https://cloud.nextcloud.com/call/c7fz9qpr), we're happy to help.

## WebRTC library

We are using our own builds of the WebRTC library. They can be found in this [repository](https://github.com/nextcloud-releases/talk-clients-webrtc).

Current version: [137.7151.0](https://github.com/nextcloud-releases/talk-clients-webrtc/releases/tag/137.7151.0).

## Running tests locally

The tests included in `talk-ios` require a running Nextcloud instance. To run this locally, make sure you have a working docker enviroment and run the file `start-instance-for-tests.sh` - this will install a Nextcloud instance, install Nextcloud Talk and wait for everything to be up and running. By default this uses the `main` branch of Nextcloud and NextcloudTalk. You can edit the file to specify a different branch (e.g. `stable27`).
After that you can run the tests directly from Xcode or alternatively from the command line you can use:

```
xcodebuild test -workspace NextcloudTalk.xcworkspace \
    -scheme "NextcloudTalk" \
    -destination "platform=iOS Simulator,name=iPhone 14,OS=16.2" \
    -test-iterations 3 \
    -retry-tests-on-failure
```

## Push notifications

If you are experiencing problems with push notifications, please check this [document](https://github.com/nextcloud/talk-ios/blob/main/docs/notifications.md) to detect possible issues.

## Credits

### Ringtones

- [Telefon-Freiton in Deutschland nach DTAG 1 TR 110-1, Kap. 8.3](https://commons.wikimedia.org/wiki/File:1TR110-1_Kap8.3_Freiton1.ogg)
  author: arvedkrynil

## TestFlight

Do you want to try the latest version in development of Nextcloud Talk iOS? Simple, follow this simple step

[Apple TestFlight](https://testflight.apple.com/join/cxzyr1eO)

We are also available on [our public Talk team conversation](https://cloud.nextcloud.com/call/c7fz9qpr), if you want to join the discussion.

**License:** [GPLv3](https://github.com/nextcloud/talk-ios/blob/main/LICENSE) with [Apple app store exception](https://github.com/nextcloud/talk-ios/blob/main/COPYING.iOS).

