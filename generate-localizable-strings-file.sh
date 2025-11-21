#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# generate-localizable-strings-file.sh

echo 'Generating Localizable.strings file...'

CURRENT_BRANCH=$(git branch --show-current)
STABLE_BRANCH=$(<.tx/backport)

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

else
  echo "On $STABLE_BRANCH branch"
fi

cd NextcloudTalk
find ../ -name "*.swift" -print0 -or -name "*.m" -not -path "../Pods/*" -print0 | xargs -0 genstrings -o en.lproj -SwiftUI
iconv -f UTF-16 -t UTF-8 en.lproj/Localizable.strings > en.lproj/Localizable-utf8.strings
mv en.lproj/Localizable-utf8.strings en.lproj/Localizable.strings
cd ..
rm -rf "$STABLE_BRANCH"
echo 'Localizable.strings file generated!'
