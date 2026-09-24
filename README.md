# SideLoador-Android

基于 [scrcpy](https://github.com/Genymobile/scrcpy) 的跨平台桌面端应用（**Windows / macOS / Linux**），用于浏览 Android 设备应用列表，并通过 **scrcpy 虚拟屏** 一键启动指定应用。

| 项 | 说明 |
|---|---|
| 产品名 | SideLoador-Android |
| 内嵌工具版 | SideLoador-Android**-bundled** |
| 版本 | 0.1.1 |
| 技术栈 | Flutter Desktop + Android companion (Java) + adb / scrcpy |

## 演示

<!-- GitHub README 会裁剪仓库内相对路径的 <video>；这里用绝对 CDN 地址，便于在线播放 -->
<video width="640" height="360" controls>
  <source src="https://github.com/baolijin/SideLoador_Android/raw/main/arts/demo.mp4" type="video/mp4">
  您的浏览器不支持 HTML5 video 标签。
</video>

<p align="center">
  <a href="https://github.com/baolijin/SideLoador_Android/raw/main/arts/demo.mp4">⬇ 下载 / 播放演示视频（约 2.5MB）</a>
</p>

---

## 功能概览

1. 启动后通过 `adb devices` 枚举 Android 设备（顶部可刷新）
2. 点击设备 → 安装并启动 **mobile-app**，回传应用列表（图标 / 名称 / 包名）
3. 网格展示第三方应用（支持搜索、侧边栏快速定位）
4. 点击应用 → 通过 scrcpy 虚拟屏启动（无需二次确认）

---

## 依赖环境

### 运行时（目标机）

| 依赖 | 作用 | 安装示例（macOS） | 安装示例（Windows） | 安装示例（Linux） |
|---|---|---|---|---|
| **adb** | 设备枚举、安装 APK、读应用列表 | `brew install --cask android-platform-tools` | [platform-tools](https://developer.android.com/tools/releases/platform-tools) 解压加入 PATH | `sudo apt install adb` |
| **scrcpy** | 虚拟屏投屏 / 启动应用 | `brew install scrcpy` | [Releases](https://github.com/Genymobile/scrcpy/releases) 安装包 | `sudo apt install scrcpy` |
| **ffmpeg** | scrcpy 编解码依赖 | 随 `brew install scrcpy` 安装 | Windows 安装包自带 | `sudo apt install ffmpeg` |

> **内嵌（bundled）包**会把 adb、scrcpy 及其动态库（含 ffmpeg 相关 dylib/so/dll）打进应用，目标机 **无需** 再安装上述依赖。  
> 宿主（host）包则 **必须** 在目标机安装 adb + scrcpy（ffmpeg 通常由 scrcpy 依赖自动带入）。

### 构建机（开发 / 打包）

| 平台 | 需要 |
|---|---|
| 通用 | Flutter SDK ≥ 3.22，Git，Python 3 |
| macOS | Xcode + Command Line Tools；可选 Android SDK（adb） |
| Windows | Visual Studio（含 C++ 桌面工作负载）+ Flutter；可选 adb |
| Linux | `clang` / `cmake` / `ninja` / GTK 开发库；可选 adb |

构建脚本默认使用国内 Flutter 镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

---

## 已验证测试环境

| 项 | 配置 |
|---|---|
| 手机 | **小米 14**（model: 23127PN0CC） |
| 系统 | **Android 16**（API 与 scrcpy 虚拟屏能力可用） |
| 桌面 | **macOS 27** / **Apple M2 Pro** |
| adb | Android SDK platform-tools 37.x |
| scrcpy | Homebrew scrcpy **4.1** |
| Flutter | stable 3.47.x（Gitee mirror） |

已验证路径：设备列表 → 部署 mobile-app → 第三方应用列表（含图标）→ 点击 scrcpy 虚拟屏启动。

---

## 架构与目录

```
scrcpy_bridge/
├── pubspec.yaml                 # Flutter 工程
├── lib/
│   ├── main.dart                # 入口（铺满系统窗口，原生标题栏）
│   ├── models/models.dart
│   ├── services/bridge_services.dart   # adb / scrcpy 解析与调用
│   └── screens/
│       ├── devices_screen.dart  # 设备列表 + 部署 mobile-app
│       └── apps_screen.dart     # 应用网格 + 虚拟屏启动
├── mobile_app/                  # Android companion（Java）
│   └── app/src/main/java/com/scrcpy/bridge/MainActivity.java
├── assets/
│   ├── scrcpy_bridge_mobile.apk # 打进桌面端的 companion APK
│   └── app_logo*.png            # 应用图标
├── scripts/
│   ├── build_host_tools.sh      # 宿主打包（mac/linux）
│   ├── build_host_tools.ps1     # 宿主打包（windows）
│   ├── build_bundled_tools.sh   # 内嵌工具打包（mac/linux）
│   ├── build_bundled_tools.ps1  # 内嵌工具打包（windows）
│   ├── _bundle_macos_dylibs.sh  # macOS dylib 收集/改写
│   └── _bundle_linux_libs.sh    # Linux so + RPATH
├── macos/  windows/  linux/     # Flutter 平台壳
└── test/                        # 单元 / widget 测试
```

### 运行时工具查找顺序（`ToolPaths`）

1. 环境变量 `ADB_PATH` / `SCRCPY_PATH`
2. **应用旁 `tools/` 目录**（bundled 包）
3. 常见系统安装路径
4. 登录 shell `command -v`

---

## 部署与集成

### A. 从源码构建（开发者）

```bash
# 1. 克隆 / 进入工程
cd scrcpy_bridge

# 2. 启用桌面目标（首次）
export PATH="$HOME/flutter-sdk/bin:$PATH"   # 若使用自定义 Flutter SDK
flutter config --enable-macos-desktop
flutter config --enable-windows-desktop
flutter config --enable-linux-desktop

# 3. 拉取依赖
flutter pub get

# 4. 自检
flutter analyze
flutter test

# 5. 开发调试
flutter run -d macos        # 或 windows / linux
```

### B. 构建不同平台的应用

Flutter **必须在对应操作系统上** 产出桌面二进制（无法从 macOS 直接打出可用的 Windows/Linux 包）。

#### 1）仅构建 Flutter 产物

```bash
# macOS
flutter build macos --release
# → build/macos/Build/Products/Release/SideLoador-Android.app

# Windows（在 Windows 机器上）
flutter build windows --release
# → build/windows/x64/runner/Release/

# Linux（在 Linux 机器上）
flutter build linux --release
# → build/linux/x64/release/bundle/
```

#### 2）一键脚本：宿主模式（HOST）

目标机 **已安装** adb + scrcpy。

| 平台 | 命令 | 产物 |
|---|---|---|
| macOS | `./scripts/build_host_tools.sh` | `/Applications/SideLoador-Android.app` |
| Linux | `./scripts/build_host_tools.sh --platform linux` | `build/linux/.../bundle/` |
| Windows | `powershell -File scripts/build_host_tools.ps1` | `build/windows/.../Release/` |

```bash
./scripts/build_host_tools.sh                 # 当前 OS
./scripts/build_host_tools.sh --platform macos
```

#### 3）一键脚本：内嵌模式（BUNDLED）

目标机 **无需** 安装 adb / scrcpy。产物名带 **`-bundled`** 后缀。

| 平台 | 命令 | 产物 |
|---|---|---|
| macOS | `./scripts/build_bundled_tools.sh` | `SideLoador-Android-bundled.app` → `/Applications/` |
| Linux | `./scripts/build_bundled_tools.sh --platform linux` | `build/linux/.../SideLoador-Android-bundled/` |
| Windows | `powershell -File scripts/build_bundled_tools.ps1` | `build/windows/.../SideLoador-Android-bundled/` |

```bash
# macOS 示例（在装有 scrcpy + adb 的 Mac 上执行）
./scripts/build_bundled_tools.sh
# 输出并安装：
#   /Applications/SideLoador-Android-bundled.app
#   Contents/MacOS/tools/{adb, scrcpy, lib/*.dylib}
```

**内嵌脚本行为简述：**

| 步骤 | macOS | Linux | Windows |
|---|---|---|---|
| 编译 | `flutter build macos` | `flutter build linux` | `flutter build windows` |
| 拷贝工具 | `tools/adb`, `tools/scrcpy` | 同左 | `tools/adb.exe`, `tools/scrcpy.exe` |
| 依赖 | 收集 dylib，`install_name_tool` 改写为 `@executable_path` | `ldd` 收集 so，`patchelf` 设 RPATH | 复制非系统 DLL 到 exe 旁 |
| 命名 | **`-bundled` 后缀** | **`-bundled` 目录名** | **`-bundled` 目录名** |

Linux 内嵌额外依赖：`patchelf`（`sudo apt install patchelf`）。

#### 4）集成到现有产品 / CI

1. **直接分发**  
   - 轻量：分发 **HOST** 包，在安装说明中要求用户安装 adb/scrcpy  
   - 绿色免装：分发 **BUNDLED** 包（体积更大，含 ffmpeg 等动态库）

2. **环境变量覆盖**（不改二进制即可换路径）：

   | 变量 | 含义 |
   |---|---|
   | `ADB_PATH` | adb 可执行文件绝对路径 |
   | `SCRCPY_PATH` | scrcpy 可执行文件绝对路径 |
   | `MOBILE_APK` | mobile-app APK 绝对路径（覆盖内置 assets） |

3. **CI 建议**  
   - macOS runner：`./scripts/build_host_tools.sh` 与 `./scripts/build_bundled_tools.sh`  
   - Windows / Linux runner：对应 `.ps1` / `.sh`  
   - 打包前执行 `flutter analyze && flutter test`  
   - 上传 `*-bundled` 与 host 两套产物，Release 页分开展示

4. **移动侧集成**  
   - 桌面端内置 `assets/scrcpy_bridge_mobile.apk`，点设备时自动 `adb install`  
   - 亦可用 `MOBILE_APK` 指定外部 APK 路径

---

## 构建 mobile-app（Android companion）

```bash
cd mobile_app
# 需要 ANDROID_HOME / JDK 17
echo "sdk.dir=$ANDROID_HOME" > local.properties

# 使用本机缓存的 Gradle（示例路径按实际调整）或：
# gradle wrapper && ./gradlew :app:assembleDebug
gradle :app:assembleDebug   # 或 ./gradlew

# 拷贝到桌面端资源
cp app/build/outputs/apk/debug/app-debug.apk \
   ../assets/scrcpy_bridge_mobile.apk
```

或使用工程根目录脚本：

```bash
./build_mobile_apk.sh
```

### mobile-app 协议（v0.1）

1. 桌面端：`adb install -r scrcpy_bridge_mobile.apk`
2. 桌面端：`adb shell am start -n com.scrcpy.bridge/.MainActivity`
3. companion 导出 JSON（含名称 / 包名 / 图标 Base64）至应用私有目录  
   `/data/data/com.scrcpy.bridge/files/scrcpy_apps.json`
4. 桌面端通过 `adb shell run-as com.scrcpy.bridge cat …` 读取  
   （失败时回退 `cmd package list packages -3`）

> 权限：`QUERY_ALL_PACKAGES` 用于 Android 11+ 枚举全部第三方应用。

---

## 运行时行为

1. 启动 → `adb devices -l` + `getprop ro.product.model`
2. 顶部刷新 → 再次拉取设备列表
3. 点击在线设备 → 安装内置 APK → 启动 companion → 合并第三方应用列表
4. 网格点击 → 立即执行 scrcpy 虚拟屏命令（无确认弹窗）

### 界面要点

- 内容区铺满系统窗口（**原生标题栏**，无 Flutter 自绘标题）
- 应用网格 **每行 8 个**，第三方优先
- 支持搜索、侧边栏字母跳转
- 应用图标为设备原始图标；无包名/3P 角标

---

## 常见问题

| 现象 | 处理 |
|---|---|
| `No such file or directory` + `adb` | 使用 bundled 包，或设置 `ADB_PATH` 为绝对路径 |
| 设备列表为空 | 打开手机 USB 调试；刷新；检查 `adb devices` |
| 第三方应用缺失 | 确认已安装新 mobile-app（含 `QUERY_ALL_PACKAGES`）；点设备重新部署 |
| 虚拟屏启动失败 | 检查 `scrcpy` 是否存在 / `SCRCPY_PATH`；查看手机 USB 调试授权 |
| bundled 包在别的 Mac 闪退 | 确认使用 `-bundled` 产物且 `tools/` 完整；`otool -L tools/scrcpy` 应无 `/opt/homebrew` 残留 |

---

## 开源版权申明

本项目桌面端与 Android companion 源码以 **Apache License 2.0** 发布（见 [`LICENSE`](./LICENSE)）。

本项目**依赖并致敬**以下开源组件，其版权归各自作者所有，使用时请遵守其许可证：

| 组件 | 许可证 | 说明 |
|---|---|---|
| [scrcpy](https://github.com/Genymobile/scrcpy) | Apache License 2.0 | 投屏与虚拟屏启动核心；本项目通过命令行调用，**未**重新分发 scrcpy 源码 |
| [Flutter](https://flutter.dev) | BSD-3-Clause（含子组件） | 桌面 UI 框架 |
| [Android SDK platform-tools / adb](https://developer.android.com/tools/releases/platform-tools) | Apache License 2.0 | 设备调试与安装 |
| FFmpeg（scrcpy 依赖） | 见 [FFmpeg 许可](https://ffmpeg.org/legal.html) | 仅在 **bundled** 包中以二进制动态库形式携带 |
| SDL / libusb 等（scrcpy 依赖） | 见各自上游许可证 | bundled 包动态库 |

**分发要求（摘要，非法律意见）：**

1. 遵守 Apache-2.0：保留版权与许可证文本；对修改进行说明（如适用）。
2. 再分发 scrcpy 或其二进制（含 bundled 内嵌）时，须附带其 Apache-2.0 许可证与版权声明。
3. FFmpeg 等组件请遵守其对应许可证；若以 LGPL/GPL 版本静态/动态链接，需满足相应源码提供或声明义务。请在对外商业分发前自行核实具体链接版本与义务。
4. 商标：`scrcpy`、`Android` 等名称仅用于兼容性描述，不暗示官方背书。

Copyright © 2026 SideLoador-Android contributors.  
Licensed under the Apache License, Version 2.0（详见 `LICENSE`）。

---

## 路线图

- [x] Flutter 三端平台壳
- [x] 双打包脚本（host / bundled，产物名区分）
- [x] mobile-app 图标与第三方列表回传
- [x] 小米 14 + Android 16 + macOS 27 联调
- [ ] 商业签名 / 公证（macOS notarization）
- [ ] 自动化 CI 三端产物上传
- [ ] 更多设备与 Android 版本回归
