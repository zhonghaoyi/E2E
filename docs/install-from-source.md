# 从源码安装 E2E

[English](install-from-source.en.md)

这个页面面向开发者。如果你只是想使用 E2E，请回到 [主页](../README.md) 下载现成的 App。

## 需要准备

- macOS 14 或更新版本
- Xcode Command Line Tools
- Git

安装 Xcode Command Line Tools：

```bash
xcode-select --install
```

## 克隆仓库

```bash
git clone https://github.com/zhonghaoyi/E2E.git
cd E2E
```

## 构建

```bash
./build.sh
```

构建完成后，App 会出现在：

```text
.build/E2E.app
```

## 安装到 Applications

```bash
cp -R .build/E2E.app /Applications/E2E.app
```

然后从 Applications 打开 E2E。

## 注意

本地构建使用 ad-hoc 签名，不是 Apple Developer ID 签名，也没有 Apple 公证。第一次打开时，macOS 可能需要你右键选择 `Open`。
