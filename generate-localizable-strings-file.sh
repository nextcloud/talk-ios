#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# generate-localizable-strings-file.sh

echo 'Generating Localizable.strings file...'

STABLE_BRANCH=stable21.1

FILE_PATHS=(
  "NextcloudTalk/*.m"
  "NextcloudTalk/*.swift"
  "ShareExtension/*.m"
  "ShareExtension/*.swift"
  "NotificationServiceExtension/*.m"
  "BroadcastUploadExtension/*.swift"
  "TalkIntents/*.swift"
  "ThirdParty/SlackTextViewController/Source/*.m"
)

STABLE_BRANCH_FILE_PATHS=(
  "NextcloudTalk/*.m"
  "NextcloudTalk/*.swift"
  "ShareExtension/*.m"
  "ShareExtension/*.swift"
  "NotificationServiceExtension/*.m"
  "BroadcastUploadExtension/*.swift"
  "TalkIntents/*.swift"
  "ThirdParty/SlackTextViewController/Source/*.m"
)

CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != $STABLE_BRANCH ]; then
  echo "Not on $STABLE_BRANCH branch, cloning $STABLE_BRANCH branch"

  REMOTE_URL=$(git config --get remote.origin.url)
  if [ -z "$REMOTE_URL" ]; then
  	echo "No remote URL found. Please check your git config."
  	exit 1
  fi

  git clone --branch $STABLE_BRANCH --single-branch --depth 1 $REMOTE_URL $STABLE_BRANCH
  cd $STABLE_BRANCH
  git submodule update --init
  cd ..

  STABLE_FILE_PATHS=()
  for path in "${STABLE_BRANCH_FILE_PATHS[@]}"; do
  	STABLE_FILE_PATHS+=("$STABLE_BRANCH/$path")
  done

else
  echo "On $STABLE_BRANCH branch"
fi

genstrings -o NextcloudTalk/en.lproj -SwiftUI ${FILE_PATHS[@]} ${STABLE_FILE_PATHS[@]}
iconv -f UTF-16 -t UTF-8 NextcloudTalk/en.lproj/Localizable.strings > NextcloudTalk/en.lproj/Localizable-utf8.strings
mv NextcloudTalk/en.lproj/Localizable-utf8.strings NextcloudTalk/en.lproj/Localizable.strings
rm -rf "$STABLE_BRANCH"
echo 'Localizable.strings file generated!'

