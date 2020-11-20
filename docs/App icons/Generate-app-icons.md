# Generate app icons from SVG

## Install Inkscape (macOS Mojave or higher)

```
$ brew tap homebrew/cask
$ brew cask install inkscape
```

## Run next commands (using Inkscape 1.0 or higher)

```
$ ruby -e '[20,29,57,40,50,72,76,1024].each { |x| `inkscape --export-type=png --export-file=talk-icon#{x}@1x.png -w #{x} icon-talk-ios.svg` }'
$ ruby -e '[40,58,80,114,120,80,100,144,152,167].each { |x| `inkscape --export-type=png --export-file=talk-icon#{x}@2x.png -w #{x} icon-talk-ios.svg` }'
$ ruby -e '[60,87,120,180].each { |x| `inkscape --export-type=png --export-file=talk-icon#{x}@3x.png -w #{x} icon-talk-ios.svg` }'
```

Note: Use `--export-filename` instead of `--export-file` when using Inkscape 1.0.1.

## Install Inkscape (old)

```
$ brew install caskformula/caskformula/inkscape
```

## Run next commands (old)

```
$ ruby -e '[20,29,57,40,50,72,76,1024].each { |x| `inkscape --export-png talk-icon#{x}@1x.png -w #{x} icon-talk-ios.svg` }'
$ ruby -e '[40,58,80,114,120,80,100,144,152,167].each { |x| `inkscape --export-png talk-icon#{x}@2x.png -w #{x} icon-talk-ios.svg` }'
$ ruby -e '[60,87,120,180].each { |x| `inkscape --export-png talk-icon#{x}@3x.png -w #{x} icon-talk-ios.svg` }'
```
