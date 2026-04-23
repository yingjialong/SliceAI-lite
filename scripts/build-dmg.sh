#!/usr/bin/env bash
# scripts/build-dmg.sh
# 用法: scripts/build-dmg.sh [version]
# 默认 version: 0.1.0
# 产物: build/SliceAI-lite-<version>.dmg
#
# 功能说明:
#   1. 使用 xcodebuild 归档 SliceAI.xcodeproj（Release 配置，unsigned）
#   2. 从 archive 中取出 .app，放入 dmg 暂存目录
#   3. 添加 /Applications 软链，方便用户拖拽安装
#   4. 用 hdiutil 打包为 UDZO 压缩格式的 .dmg
#
# 约束:
#   - MVP v0.1 明确不做代码签名与公证，故显式禁用代码签名
#   - 本脚本仅在 macOS 上运行，依赖 Xcode 命令行工具
set -euo pipefail

# 切换到项目根目录，使脚本不依赖调用者所在的工作目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# 版本号：优先使用第一个参数，未提供则回退到 0.1.0
VERSION="${1:-0.1.0}"
SCHEME="SliceAI"
PROJECT="SliceAI.xcodeproj"
BUILD_DIR="build"
EXPORT_DIR="$BUILD_DIR/export"
DMG_STAGING="$BUILD_DIR/dmg-staging"

echo "[build-dmg] Project root: $PROJECT_ROOT"
echo "[build-dmg] Building version: $VERSION"

# 前置检查：Xcode 命令行工具必须存在
command -v xcodebuild >/dev/null 2>&1 || {
    echo "[build-dmg] Error: xcodebuild not found. Install Xcode or Command Line Tools." >&2
    exit 1
}

# 前置检查：Xcode 工程文件必须存在（Task 37 创建）
if [[ ! -d "$PROJECT" ]]; then
    echo "[build-dmg] Error: $PROJECT not found in $PROJECT_ROOT." >&2
    echo "[build-dmg] Run Task 37 first to create the Xcode project." >&2
    exit 1
fi

# 清理并重建 build 目录，避免旧产物干扰
echo "[build-dmg] Cleaning $BUILD_DIR ..."
rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR" "$DMG_STAGING"

# 归档（unsigned）
# CODE_SIGN_IDENTITY=""、CODE_SIGNING_REQUIRED=NO、CODE_SIGNING_ALLOWED=NO
# 三项共同确保 archive 不触发任何代码签名流程。
echo "[build-dmg] Archiving $SCHEME (unsigned) ..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/SliceAI-lite.xcarchive" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    archive

# 从 archive 中取出 .app 到暂存目录
echo "[build-dmg] Copying .app to staging ..."
cp -R "$BUILD_DIR/SliceAI-lite.xcarchive/Products/Applications/SliceAI-lite.app" "$DMG_STAGING/"

# 创建 Applications 软链，标准 DMG 安装体验（拖拽到 Applications）
ln -s /Applications "$DMG_STAGING/Applications"

# 打包 dmg（UDZO：压缩、只读，分发友好）
DMG_PATH="$BUILD_DIR/SliceAI-lite-$VERSION.dmg"
echo "[build-dmg] Creating DMG: $DMG_PATH ..."
hdiutil create -volname "SliceAI-lite $VERSION" \
    -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

echo "[build-dmg] Built: $DMG_PATH"
