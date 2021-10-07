#!/usr/bin/env bash

# generate-localizable-strings-file.sh

echo 'Generating Localizable.strings file...'
cd NextcloudTalk
genstrings -o en.lproj *.m *.swift ../ShareExtension/*.m ../NotificationServiceExtension/*.m ../ThirdParty/SlackTextViewController/Source/*.m
iconv -f UTF-16LE -t UTF-8 en.lproj/Localizable.strings > en.lproj/Localizable-utf8.strings
mv en.lproj/Localizable-utf8.strings en.lproj/Localizable.strings
echo 'Localizable.strings file generated!'

