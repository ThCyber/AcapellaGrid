<div align="center">

<img src="docs/images/icon.png" width="128" alt="Acapella Grid 图标">

# Acapella Grid

**一个人唱完一首阿卡贝拉的所有声部，录成四宫格分屏视频，而且四个声部严丝合缝地对齐。**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#安装)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AVFoundation-F05138?logo=swift&logoColor=white)](#从源码构建)
[![下载](https://img.shields.io/github/v/release/ThCyber/AcapellaGrid?label=下载)](https://github.com/ThCyber/AcapellaGrid/releases/latest)

[English](README.md) · 简体中文

<img src="docs/images/playing.jpg" width="820" alt="四个声部同步回放">

</div>

## 为什么做这个

一个人录多声部阿卡贝拉看起来很简单：先录女高音，再跟着它录女中音，依次叠加。但实际上，每叠一层都会慢一点点。Mac 把伴奏送到你耳机里要花时间，你的声音从麦克风回到电脑也要花时间。叠到第四层时，男低音已经明显落后于女高音了。

Acapella Grid 从两方面解决这个问题：

- **帮你唱准**：除了能听到的节拍器，还有**可视化节拍器**：预备拍倒数、节拍指示条、每一拍都会闪的边框。拍子不光能听到，还能看到。
- **帮机器对齐**：统一时钟、实测延迟补偿、单一时间线回放。唱得再准也解决不了的机器误差，由这些来消除。

## 功能

- 🎛 **四宫格**：点击空格子就开始录这个声部，其他声部同时伴奏
- 🥁 **可视 + 可听节拍器**：速度、拍号（2/4–7/4）、预备拍都可调，每小节第一拍有重音
- 🎯 **延迟校准**：约 5 秒测出你这套设备的来回延迟
- 🎼 **保留弱起**：第 1 小节之前的那一小节也会录进去，弱起音不会被切掉
- 〰️ **对齐视图**：所有音轨的波形画在同一张节拍网格上，可按 ±1 / ±10 毫秒微调
- 🔇 **单轨控制**：任意格子都可以重录、静音、删除
- 📼 **导出**：1080p MP4 四宫格视频，和你在 App 里听到的完全一致

| 录音前的预备拍 | 对齐视图 | 延迟校准 |
|:--:|:--:|:--:|
| <img src="docs/images/count-in.jpg" width="270"> | <img src="docs/images/align.jpg" width="270"> | <img src="docs/images/calibrate.jpg" width="270"> |

> 截图使用的是 [`Tools/make_demo.swift`](Tools/make_demo.swift) 生成的卡通演示项目。

## 安装

1. 从 [最新 Release](https://github.com/ThCyber/AcapellaGrid/releases/latest) 下载 **`AcapellaGrid.zip`** 并解压。
2. 把 **AcapellaGrid.app** 拖进 **应用程序（Applications）** 文件夹。
3. 这个 App 没有经过 Apple 公证，所以第一次打开需要多做一步，二选一：
   - 右键点击 App → **打开** → **打开**；或者
   - 在终端执行一次：
     ```bash
     xattr -dr com.apple.quarantine /Applications/AcapellaGrid.app
     ```
4. 弹出提示时，允许访问**摄像头**和**麦克风**。如果不小心点了拒绝，到「系统设置 → 隐私与安全性」里重新打开。

支持 Apple 芯片和 Intel 芯片的 Mac（都是原生运行），需要 macOS 14 Sonoma 或更新版本。

## 使用教程

### 1. 开始之前：耳机和校准

**录音时请戴有线耳机。** 如果伴奏或节拍器的声音从扬声器放出来，麦克风会把它们一起录进去。也不要用蓝牙耳机：它会增加 150–300 毫秒的延迟，而且延迟一直在变，固定的补偿没法修正。

然后点击工具栏的 **Calibrate（校准）**。每套音频设备做一次就行；换耳机或声卡后再做一次。

| 你的设备 | 怎么做 |
|---|---|
| 扬声器 | 拔掉耳机，调大音量，保持安静。点击 **Run Calibration**，麦克风会直接听到 10 声咔哒。 |
| 耳机 | 点击 **Run Calibration**，然后**跟着 10 声咔哒用力拍手**。这样也会把你自己的节奏感算进去，而你唱歌时依靠的正是这种节奏感。 |

结果会显示成 *"Measured 38 ms from 10 of 10 clicks · Spread ±2 ms"*。如果误差范围（Spread）超过约 15 毫秒，说明这次测得不稳，再测一次。也可以用 **Manual** 滑块手动设定数值。当前使用的补偿值一直显示在主窗口右下角。

### 2. 设置歌曲

工具栏里可以设置：

- **Tempo**：速度，直接输入 BPM 或用箭头调
- **Meter**：拍号，每小节几拍（2/4 到 7/4）
- **Count-in**：开录前先听几个小节的预备拍（1–4 小节）
- **Click**：录音时和回放时是否响节拍器，以及音量

> ⚠️ 请在录第一个声部**之前**定好速度和拍号。录完再改，节拍网格就和已录的音轨对不上了。

### 3. 录第一个声部

1. 点击一个空格子，比如 **Track 1**。
2. 这个格子会切换成摄像头画面，**预备拍**开始：屏幕上显示大大的 **1 2 3 4**，边框闪橙色。
3. **最后一个预备小节已经开始录了**（格子里会提示 *"Get ready — pickups are recorded"*），弱起音就在这里唱。
4. 到第 1 小节时，角标变成 **● REC**，边框变红，网格上方的节拍条显示「Bar · Beat」（第几小节第几拍）。留意每小节第一拍的大圆点。
5. 唱完后，**再点一次这个格子，或者按空格键**停止。

如果在预备拍阶段就停止，这一条不会保存。

### 4. 叠加其他声部

点击下一个空格子。你唱的时候，所有已录好的声部都会一起播放，节拍器也在同一条节拍网格上继续。重复这个过程，直到四个格子都录满。

### 5. 回放

按 **Play** 或**空格键**。所有声部从同一条时间线播放，每个有内容的格子会跟着节拍闪，方便你用眼睛检查对得准不准。

### 6. 用 Align 微调（可选）

打开 **Align（对齐）**，可以看到每条音轨的波形画在同一张节拍网格上：

- 细线是拍，粗线是小节线，**红线**是第 1 小节第 1 拍。
- 如果某个声部的辅音总是比线早一点或晚一点，用 **−10 / −1 / +1 / +10 ms** 微调；**Reset** 撤销微调。
- 用上方的步进按钮缩放（显示几个小节）和前后移动。

当前的微调值也会显示在对应格子的角落，例如 `+6 ms`。

### 7. 管理音轨

鼠标移到有内容的格子上，会出现按钮：

| 按钮 | 作用 |
|:--:|---|
| ↺ | 重录这个声部（新的一条录完后才替换旧的） |
| 🔈 | 静音 / 取消静音 |
| 🗑 | 删除这条录音（会先确认） |

### 8. 导出

点击 **⋯ → Export Grid Video…**，选择保存位置。你会得到一个 1920×1080 的四宫格 MP4，里面混合了所有未静音的声部。导出完成后会在访达里显示这个文件。

### 9. 文件存在哪里

录音会自动保存在 `~/Movies/AcapellaGrid/Current Project/`（「影片」文件夹里）。**⋯ → Show Project Folder** 可以打开它，**⋯ → Clear All Tracks** 清空所有音轨、开始一首新歌。**⋯ → Mirror Video** 控制画面左右镜像，默认开启，因为这样看起来像照镜子。

## 常见问题

| 问题 | 解决办法 |
|---|---|
| 每叠一层都感觉慢一点 | 插着你现在用的耳机，重新做一次 **Calibrate**。 |
| 某一个声部总是对不齐 | 打开 **Align**，只微调那一条。 |
| 后录的音轨里能听到前面的声部 | 你在用扬声器录音，换成耳机。 |
| 提示 "Camera and microphone access is needed" | 系统设置 → 隐私与安全性 → 摄像头 / 麦克风 → 打开 AcapellaGrid。 |
| macOS 提示 App「无法打开」 | 见[安装](#安装)第 3 步。 |

## 同步原理

```
 预备拍咔哒 …  │  引入小节  │ 第1小节 │ 第2小节 │ …
              ▲ 时间线 0   ▲ 歌曲开始（第 0 拍）
              │
   录音文件的 0 秒 ═ 伴奏的 0 秒 ═ 引入小节的第一声咔哒
   都安排在未来同一个 mach 主机时间点开始
```

1. **统一时钟**：节拍器（`AVAudioEngine`）、伴奏（`AVPlayer.setRate(_:time:atHostTime:)`）和录音（`AVCaptureSession` → `AVAssetWriter.startSession(atSourceTime:)`）都按 mach 主机时钟排在约 350 毫秒后的同一时刻开始。没有哪个组件是「立刻」开始的，所以各自的启动耗时不会影响对齐。
2. **来回延迟补偿**：校准时在已知的主机时间播放咔哒，在麦克风采样（同一个时钟）里找到它们的起始点，取中位数作为延迟。每条录音都保存录制时使用的补偿值，并按这个值整体往前移。
3. **单一合成**：所有录音放在同一个 `AVMutableComposition` 上，用 `AVVideoComposition` 画出四宫格。回放只用一个播放器，所以声部之间不会漂移；导出的也是同一个合成。
4. **可视节拍器**：由同一个主机时间位置驱动，并减去输出设备的延迟，让闪光和你听到的咔哒同时出现。

## 从源码构建

需要 Xcode 16 或更新版本（项目使用了文件夹同步分组）和 macOS 14+。

```bash
git clone https://github.com/ThCyber/AcapellaGrid.git
cd AcapellaGrid
open AcapellaGrid.xcodeproj   # 然后按 ⌘R
```

或者用命令行构建：

```bash
xcodebuild -project AcapellaGrid.xcodeproj -scheme AcapellaGrid -configuration Release -derivedDataPath build build
```

几个实用的小工具：

- `swift Tools/make_icon.swift icon.png`：渲染 App 图标
- `swift Tools/make_demo.swift ~/Desktop/demo`：生成卡通演示项目，用下面的命令打开：
  `open -n AcapellaGrid.app --args -ProjectFolder ~/Desktop/demo`

### 项目结构

```
AcapellaGrid/
├── Transport.swift           # 在同一条主机时间线上协调录音、回放和校准
├── Metronome.swift           # 按绝对主机时间排程的 AVAudioEngine 节拍器
├── CaptureRecorder.swift     # 摄像头 + 麦克风 → AVAssetWriter，在精确的主机时间开始
├── CompositionBuilder.swift  # 把各条录音放到同一条时间线上，渲染四宫格
├── LatencyCalibration.swift  # 检测咔哒起始点，计算来回延迟
├── Project.swift             # 设置和音轨，保存为 project.json
├── HostTime.swift            # mach 主机时间工具函数
└── Views/                    # SwiftUI 界面：网格、节拍条、对齐、校准
```
