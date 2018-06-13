# Nextcloud Talk iOS app

Video & audio calls through Nextcloud on iOS.

[![Available on the AppStore](https://github.com/nextcloud/talk-ios/blob/master/docs/App%20Store/Download_on_the_App_Store_Badge.svg)](https://itunes.apple.com/app/id1296825574)

## Prerequisites

- [Nextcloud server](https://github.com/nextcloud/server) version 13 or higher.
- [Nextcloud Talk](https://github.com/nextcloud/spreed) version 3.0 or higher.
- [CocoaPods](https://cocoapods.org/)

## Build steps

```
$ pod install
$ open VideoCalls.xcworkspace
```

### Installing

There are several ways of installing Talk. If you just need to enable local access it's enough to just enable the app from the Nextcloud App Store. 

If you need to use Talk from outside your own LAN, or through a strict firewall you need to install and setup a TURN server. That's a bit more tricky, but the guys from [Nextcloud VM](https://github.com/nextcloud/vm) has developed a script that can be used which takes care of everything for you. You can find the script [here](https://github.com/nextcloud/vm/blob/master/apps/talk.sh). The script is tested on Ubuntu Server 18.04, but should work on 16.04 as well. Please keep in mind that it's developed for the VM specifically and any issues should be reported in that repo, not here.

**Here's a short video on how it's done:**<br>
[![Install Talk on Nextcloud](https://lh3.googleusercontent.com/crCv9cBtaOz-5BqpXp0Dhxjq3kyh5rbg0oKx2_BlCwZe2i3nuGhkK2zIzzdCMXFVal8=s180)](https://youtu.be/KdTsWIy4eN0)

## Start contributing
If you want to [contribute](https://nextcloud.com/contribute/), you are very welcome: 

- on our IRC channels #nextcloud and #nextcloud-mobile (on freenode)
- our forum at https://help.nextcloud.com/

[![irc](https://img.shields.io/badge/IRC-%23nextcloud%20on%20freenode-orange.svg)](https://webchat.freenode.net/?channels=nextcloud)
[![irc](https://img.shields.io/badge/IRC-%23nextcloud--mobile%20on%20freenode-blue.svg)](https://webchat.freenode.net/?channels=nextcloud-mobile)

Fork this repository and contribute back using pull requests to the master branch!

**License:** [GPLv3](https://github.com/nextcloud/spreed-ios/blob/master/LICENSE) with [Apple app store exception](https://github.com/nextcloud/spreed-ios/blob/master/COPYING.iOS).

