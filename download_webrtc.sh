#!/bin/bash

set -euo pipefail

DOWNLOAD_FILE=$(mktemp  -u)

curl -L "https://github.com/nextcloud-releases/talk-clients-webrtc/releases/download/108.5359.0/WebRTC.xcframework.zip" -o "$DOWNLOAD_FILE"

unzip -qq "$DOWNLOAD_FILE" -d "ThirdParty"
rm "$DOWNLOAD_FILE"


