#!/bin/bash

set -euo pipefail

DOWNLOAD_FILE=$(mktemp  -u)
UNZIP_DESTINATION="ThirdParty"
WEBRTC_VERSION="108.5359.0"
DOWNLOAD_URL="https://github.com/nextcloud-releases/talk-clients-webrtc/releases/download/$WEBRTC_VERSION/WebRTC.xcframework.zip"

curl -L "$DOWNLOAD_URL"  -o "$DOWNLOAD_FILE"

unzip -qq "$DOWNLOAD_FILE" -d "$UNZIP_DESTINATION"
rm "$DOWNLOAD_FILE"
