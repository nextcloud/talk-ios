# Generate localization file

## Using genstrings tool

```
$ genstrings -o en.lproj *.m
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