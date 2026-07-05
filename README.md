<!--
  - SPDX-FileCopyrightText: 2017 Nextcloud GmbH and Nextcloud contributors
  - SPDX-FileCopyrightText: 2026 ironkingironking
  - SPDX-License-Identifier: GPL-3.0-or-later
-->
# Movena Talk iOS fork

**Native iPhone controls for the Movena SIP/PSTN dialout bridge, based on Nextcloud Talk for iOS**

This repository is a Movena-focused fork of the upstream
[Nextcloud Talk iOS app](https://github.com/nextcloud/talk-ios). The upstream
app provides secure Nextcloud Talk chat and calls; this fork adds the iOS-side
controls needed to invite and manage phone participants through Movena's
SIP/PSTN bridge.

The adaptation is deliberately server-driven: the iPhone app does not embed SIP
credentials or run a local SIP stack. It calls the configured Nextcloud
Talk/Movena OCS APIs, and the Movena HPB/PBX bridge handles the actual
SIP/PSTN leg.

## Movena contribution

This fork makes the Movena work visible inside the native iOS call experience:

- adds a **Call phone number** action for moderators inside a Talk call
- adds **Phone controls** for DTMF, transfer start, transfer hold, transfer
  complete, transfer cancel, and phone hangup
- recognizes Talk's `sip-support-dialout` capability before showing phone
  actions
- supports phone participants with the `phones` actor type
- sends the Movena bridge requests through native Swift API wrappers

## Implementation map

| Area | Files | Purpose |
| --- | --- | --- |
| Call UI | `NextcloudTalk/Calls/CallViewController.swift` | Adds the moderator dialout entry and in-call phone controls. |
| Talk API client | `NextcloudTalk/Network/NCAPIController.swift` | Adds phone attendee, dialout, DTMF, transfer, and hangup OCS requests. |
| Capability handling | `NextcloudTalk/Database/NCDatabaseManager.swift` | Adds `sip-support-dialout` capability detection. |
| Participant model | `NextcloudTalk/Rooms/NCRoomParticipant.swift` | Adds phone participant helpers used by the call UI. |
| User actor constants | `NextcloudTalk/Contacts/NCUser.h`, `NextcloudTalk/Contacts/NCUser.m` | Adds the `phones` participant actor type. |

For deeper architecture notes, runtime requirements, endpoint details, and test
notes, see [docs/movena-sip-dialout.md](docs/movena-sip-dialout.md).

## Runtime requirements

The Movena controls appear only when the signed-in account and room can support
the bridge flow:

- the user is in a call and has moderator permissions
- the server advertises the `sip-support-dialout` Talk capability
- the Movena HPB/PBX bridge endpoints are deployed server-side
- the Nextcloud Talk backend accepts phone attendee and dialout requests

## Upstream base

This fork keeps the upstream Nextcloud Talk iOS foundation. The original app is
a fully on-premises audio/video and chat communication service with web and
mobile clients, designed for secure communication through Nextcloud.

[![Available on the AppStore](https://github.com/nextcloud/talk-ios/blob/main/docs/App%20Store/Download_on_the_App_Store_Badge.svg)](https://itunes.apple.com/app/id1296825574)

## Prerequisites

- [Nextcloud server](https://github.com/nextcloud/server) version 22 or higher (that fulfills [ATS requirements](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW57)).
- [Nextcloud Talk](https://github.com/nextcloud/spreed) version 12.0 or higher.
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

Current version: [147.7727.0](https://github.com/nextcloud-releases/talk-clients-webrtc/releases/tag/147.7727.0).

## Running tests locally

The tests included in `talk-ios` require a running Nextcloud instance. To run this locally, make sure you have a working docker enviroment and run the file `start-instance-for-tests.sh` - this will install a Nextcloud instance, install Nextcloud Talk and wait for everything to be up and running. By default this uses the `main` branch of Nextcloud and NextcloudTalk. You can edit the file to specify a different branch (e.g. `stable33`).
After that you can run the tests directly from Xcode or alternatively from the command line you can use:

```
xcodebuild test -workspace NextcloudTalk.xcworkspace \
    -scheme "NextcloudTalk" \
    -destination "platform=iOS Simulator,name=iPhone 16,OS=18.5" \
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
