#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# generate-localizable-strings-file.sh

echo 'Generating Localizable.strings file...'
cd NextcloudTalk
genstrings -o en.lproj -SwiftUI *.m *.swift ../ShareExtension/*.m ../ShareExtension/*.swift ../NotificationServiceExtension/*.m ../BroadcastUploadExtension/*.swift ../TalkIntents/*.swift ../ThirdParty/SlackTextViewController/Source/*.m
iconv -f UTF-16 -t UTF-8 en.lproj/Localizable.strings > en.lproj/Localizable-utf8.strings
mv en.lproj/Localizable-utf8.strings en.lproj/Localizable.strings
echo 'Localizable.strings file generated!'

