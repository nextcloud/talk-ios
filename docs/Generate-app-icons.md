# Generate app icons from SVG

## Install Inkscape

```
$ brew install caskformula/caskformula/inkscape
```

## Install Inkscape (macOS Mojave)

```
$ brew tap homebrew/cask
$ brew cask install inkscape
```

## Run next commands

```
$ ruby -e '[29,57,40,50,72,76,1024].each { |x| `inkscape --export-png talk-icon#{x}@1x.png -w #{x} icon-talk-ios.svg` }'
$ ruby -e '[40,58,80,114,120,80,100,144,152,167].each { |x| `inkscape --export-png talk-icon#{x}@2x.png -w #{x} icon-talk-ios.svg` }'
$ ruby -e '[60,87,120,180].each { |x| `inkscape --export-png talk-icon#{x}@3x.png -w #{x} icon-talk-ios.svg` }'
```

**Source:** http://throwachair.com/2013/10/26/generate-all-your-ios-app-icons-with-svg-and-inkscape/
