#!/bin/bash
# 生成 Xcode 工程并打开。依赖 XcodeGen：brew install xcodegen
set -e
cd "$(dirname "$0")"

if ! command -v xcodegen &> /dev/null; then
    echo "未检测到 xcodegen，正在通过 Homebrew 安装..."
    brew install xcodegen
fi

xcodegen generate
open AITokenUsageWidget.xcodeproj
echo "完成。请在 Xcode 中为两个 target 选择你的 Team（Signing & Capabilities），然后运行 App。"
