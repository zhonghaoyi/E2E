# Install E2E From Source

[中文](install-from-source.md)

This page is for developers. If you only want to use E2E, go back to the [home page](../README.en.md) and download the ready-to-run app.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools
- Git

Install Xcode Command Line Tools:

```bash
xcode-select --install
```

## Clone

```bash
git clone https://github.com/zhonghaoyi/E2E.git
cd E2E
```

## Build

```bash
./build.sh
```

The built app appears here:

```text
.build/E2E.app
```

## Install To Applications

```bash
cp -R .build/E2E.app /Applications/E2E.app
```

Then open E2E from Applications.

## Note

Local builds use an ad-hoc signature, not an Apple Developer ID signature or Apple notarization. On first launch, macOS may require you to right-click the app and choose `Open`.
