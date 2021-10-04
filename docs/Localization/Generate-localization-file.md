# Generate localization file

## Using genstrings tool

```
$ cd NextcloudTalk
$ genstrings -o en.lproj *.m *.swift ../ShareExtension/*.m ../NotificationServiceExtension/*.m ../ThirdParty/SlackTextViewController/Source/*.m ../ThirdParty/AppRTC/*.m
```

## Showing .strings file diff

Add this to .gitattributes file in root folder:
```
*.strings diff=localizablestrings
```

Add this to your ~/.gitconfig file:
```
[diff "localizablestrings"]
	textconv = "iconv -f utf-16 -t utf-8"
```
