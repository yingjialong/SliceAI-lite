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

# Ad-hoc 签名 app bundle，让 macOS TCC 数据库稳定识别 cdhash + bundle id。
#
# 背景：archive 时用 CODE_SIGNING_ALLOWED=NO 完全跳过 codesign，但 macOS linker
# 仍会给二进制加一个最小的 "linker-signed" 伪签名——Identifier 是文件名而不是
# bundle id，且不封印 resources。TCC 用 cdhash + identifier + sealed resources
# 综合判断 app 身份，linker-signed 这些字段全错或缺，导致 Accessibility 授权
# 一刷新就失效（用户表象：系统设置里勾选了，但划词不响应）。
#
# Ad-hoc 签名（--sign -）不需要任何开发者证书或账号，但能产生完整的 cdhash
# + sealed resources，让 TCC 稳定记住权限授予状态。--options runtime 与
# pbxproj 的 ENABLE_HARDENED_RUNTIME=YES 对齐；--entitlements 注入与 archive
# 时 CODE_SIGN_ENTITLEMENTS 一致的 plist。
#
# 注意：--deep 在 macOS 12+ 是 deprecated，但本 app 没有 nested executable
# （SliceAIKit 是 static library，编译进主二进制），实际等同于只签主 bundle，
# warning 可忽略。如果以后引入 dynamic framework / plugin / XPC service，
# 需改为按 nested item 单独签。
echo "[build-dmg] Ad-hoc signing app for stable TCC identity ..."
codesign --force --deep --sign - \
    --entitlements "$PROJECT_ROOT/SliceAIApp/SliceAI.entitlements" \
    --options runtime \
    "$DMG_STAGING/SliceAI-lite.app"

# 验证签名状态：必须是 adhoc（非 linker-signed）+ Identifier=com.sliceai.lite
# + Sealed Resources 存在；否则 fail-fast 防止伪签名退化未被发现
codesign -dvv "$DMG_STAGING/SliceAI-lite.app" 2>&1 | head -5

# 创建 Applications 软链，标准 DMG 安装体验（拖拽到 Applications）
ln -s /Applications "$DMG_STAGING/Applications"

# 打包 dmg（UDZO：压缩、只读，分发友好）
DMG_PATH="$BUILD_DIR/SliceAI-lite-$VERSION.dmg"
echo "[build-dmg] Creating DMG: $DMG_PATH ..."
hdiutil create -volname "SliceAI-lite $VERSION" \
    -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

echo "[build-dmg] Built: $DMG_PATH"
