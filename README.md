# Deep-Fried Audio Player

Deep-Fried Audio Player 是一个 iOS / iPadOS 优先的 SwiftUI 音频处理 App。目标是让用户把正常音频加工成 deep-fried / 全损 / 油炸音质，并能在单个模块模式和工作流模式之间切换。

当前项目是 Xcode 生成的 SwiftUI App，target 名为 `Deep-Fried Audio Player`，入口在 `Deep-Fried Audio Player/Deep_Fried_Audio_PlayerApp.swift`。

## Platform

优先级：

1. iOS
2. iPadOS
3. macOS 后续再评估

首版设计应以触屏交互为主，兼顾 iPad 横屏的大画布和侧栏编辑体验。

## Product Modes

### Single Module Mode

单个模块模式用于快速测试一种降质效果。

- 一次只启用一个音质破坏模块。
- 用户选择模块、调整参数、预览输出。
- 支持保存该模块的参数为模块预设。
- 支持把当前模块发送到工作流模式继续组合。

### Workflow Mode

工作流模式用于搭建完整 deep-fried audio 处理链。

- 用户可以添加多个模块。
- 模块从上到下依次处理音频。
- 用户可以启用/禁用、复制、删除和重新排序模块。
- 每个模块都有独立参数。
- 用户可以保存完整工作流预设。

## Core Features

- 导入音频文件。
- 使用麦克风录音。
- 生成示例音频用于调试。
- 播放原音频、单模块输出、工作流输出。
- 显示原始波形和处理后波形。
- 参数变化后重新生成预览结果。
- 自动化测试不触发外放播放。

## Effect Modules

所有模块都必须支持自定义参数。README 只定义产品规格，不规定具体 DSP 或 codec 实现方法。

- Bitrate Reduction：降低码率，例如 `320/128/64/32/16/8 kbps`。
- Low Quality Codec：真实编码往返优先，覆盖 MP3、AAC、Opus、AMR-NB、Speex、G.711、G.729；不可用 codec 必须明确显示不可用或后续支持。
- Sample Rate Reduction：降低采样率，例如 `44100/22050/16000/11025/8000 Hz`。
- Low-pass：砍掉高频。
- High-pass：砍掉低频。
- Band-pass：只保留中间频段。
- Notch：挖掉指定频率附近的声音。
- Random Frequency Response：让不同频段随机变大或变小。
- Bit Depth Reduction：降低位深，例如 `16/8/6/4/2-bit`。
- Clipping：硬削波，制造爆麦和 deep-fried 失真。
- Compressor：过度压缩动态范围。
- Limiter：拉高响度并限制峰值。
- FFT / Spectral Damage：频域破坏模块族，作为可选模块，不是核心路线。

## Current Project Layout

```text
Deep-Fried Audio Player.xcodeproj
Deep-Fried Audio Player/
  Deep_Fried_Audio_PlayerApp.swift
  ContentView.swift
Deep-Fried Audio PlayerTests/
Deep-Fried Audio PlayerUITests/
```

## Development Notes

- UI 使用 SwiftUI。
- 音频导入、解码、播放和录音优先使用 AVFoundation。
- 波形、频谱和分析能力可使用 Accelerate/vDSP。
- iOS/iPadOS 权限要明确处理，包括麦克风权限、文件导入权限和后台处理状态。
- 播放控制必须保证同一时间只播放一个源。
- 输出音频需要安全保护，避免明显爆音。
- 所有用户可见文案必须使用 `Localizable.xcstrings`，不要在 SwiftUI 视图里硬编码长文案。
- 默认本地化语言为简体中文 `zh-Hans` 和英文 `en`，App 应跟随系统语言。

## Test Expectations

自动化测试优先覆盖：

- 单个模块模式可以选择模块并修改参数。
- 工作流模式可以添加、删除、排序、启用/禁用模块。
- 参数变化会触发预览结果重新生成。
- 输出数据没有 `NaN` 或无穷值。
- 不可用 codec 有明确状态。
- 用户可见文案来自 `Localizable.xcstrings`。
- 自动化测试不点击播放按钮。

人工验收覆盖：

- iPhone 竖屏可用。
- iPad 横屏可用。
- 导入或录制音频后可以看到波形。
- 单模块输出和工作流输出能被用户手动播放。
- deep-fried 效果听感明显。

## Changelog Policy

以后每次修改项目都必须同步更新 `CHANGELOG.md`。需要记录的变更包括功能、文档、架构、测试、依赖、项目配置和用户可见行为变化。
