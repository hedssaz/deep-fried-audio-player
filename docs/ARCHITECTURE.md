# Deep-Fried Audio Player Architecture

本文档说明 Deep-Fried Audio Player 的目标架构。当前仓库仍以 Xcode SwiftUI 模板为基础，本文定义 v1 逐步实现时应遵守的边界和数据流。

## Platform Priority

Deep-Fried Audio Player 是 iOS / iPadOS 优先的 SwiftUI App。

优先级：

1. iOS
2. iPadOS
3. macOS 后续再评估

v1 的交互设计以触屏为默认输入方式。iPhone 竖屏应先可用，iPadOS 再扩展为更适合横屏和侧栏编辑的体验。即使 Xcode 项目设置中存在 macOS 或其他平台支持，核心架构也不应为了这些平台提前复杂化。

## Layered SwiftUI Architecture

推荐分层：

```text
SwiftUI Views
  -> ViewModels / Observable state
    -> Audio services
    -> Workflow engine
      -> Effect processors
        -> AudioBuffer
```

目录可以按以下模块逐步扩展：

```text
Deep-Fried Audio Player/
  App/
  Models/
  Audio/
  Effects/
  Workflow/
  Presets/
  Views/
```

职责边界：

- SwiftUI Views 只负责布局、用户输入和状态展示。
- ViewModels 持有用户当前项目状态，并把 UI action 转换成服务调用。
- Audio services 负责导入、录音、播放、示例音频生成和 AVFoundation 适配。
- Workflow engine 负责把 `Workflow` 渲染为新的 `AudioBuffer`。
- Effect processors 只处理音频变换，不依赖 SwiftUI。
- Models 必须保持可测试、可编码、尽量无 UI 依赖。

所有 UI 状态变更应在 `@MainActor` 上发生。耗时音频处理应离开主线程执行，并把结果安全地合并回 UI 状态。

## Core App State

顶层状态由 `AudioProjectViewModel` 统一协调。

它应持有：

- 当前产品模式：Single Module Mode 或 Workflow Mode。
- 原始 `AudioBuffer`。
- 已处理的预览 `AudioBuffer`。
- 当前单模块配置。
- 当前 `Workflow`。
- 处理状态：empty、dirty、processing、ready、failed。
- 播放状态：stopped、playing original、playing processed。

Single Module Mode 不需要单独的处理管线。它应被建模为一个临时 workflow：只包含一个启用的 `EffectBlock`。这样单模块和工作流模式可以共用 `WorkflowRenderer`、`EffectProcessor`、预设和测试逻辑。

## AudioBuffer Data Flow

`AudioBuffer` 是内部 DSP 和渲染管线的核心数据结构，表示解码后的 PCM 音频。

建议字段：

- `sampleRate: Double`
- `channelCount: Int`
- `frames: Int`
- `samples: [[Float]]`
- `duration: TimeInterval`

数据流：

```text
File Import / Recording / SampleAudioFactory
  -> AudioBuffer original
  -> AudioProjectViewModel marks preview dirty
  -> WorkflowRenderer receives original + Workflow
  -> EffectProcessor chain transforms AudioBuffer
  -> output safety clamp / limiter
  -> AudioBuffer processed preview
  -> WaveformView and manual playback
```

处理规则：

- 内部处理统一使用 `Float` samples。
- 尽量保留多声道数据；只支持单声道的效果必须显式 downmix，并在行为上可解释。
- 每个处理器都必须返回有限样本，不能产生 `NaN` 或 infinity。
- 参数、模块顺序或启用状态变化后，现有处理结果必须标记为 stale / dirty。
- 自动生成预览不能触发外放播放。

## WorkflowRenderer

`WorkflowRenderer` 是工作流渲染入口，负责把原始 buffer 通过有序 effect chain 变成处理后的 preview buffer。

职责：

- 接收 `AudioBuffer` 和 `Workflow`。
- 按 workflow 中的顺序过滤启用的 `EffectBlock`。
- 调用对应的 `EffectProcessor`。
- 在最终输出处做安全峰值限制或归一化，避免明显爆音。
- 返回新的 `AudioBuffer`。
- 支持取消；新渲染开始时应取消旧渲染。
- 把错误定位到具体失败的 block，供 UI 显示可读错误。

`WorkflowRenderer` 不应负责播放、文件导入、录音权限、SwiftUI 布局或预设持久化。

## EffectProcessor

每一种效果类型映射到一个 processor。

建议协议：

```swift
protocol EffectProcessor {
    var type: EffectType { get }
    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer
}
```

处理器边界：

- 输入是 typed `AudioBuffer` 和 typed `EffectBlock`。
- 参数来自 `EffectParameter`，避免用裸字典在处理器里猜类型。
- 禁用 block 应由 renderer 旁路，processor 可以假设收到的是启用 block。
- processor 输出长度、采样率或声道数如有变化，必须符合该效果的定义。
- codec 类效果必须区分真实 encode/decode 往返和不可用状态；不要把模拟结果标成真实 codec 输出。

第一阶段优先实现不依赖外部 codec 的模块，例如 Sample Rate Reduction、Bit Depth Reduction、Clipping、Filter / EQ、Compressor、Limiter 和 Spectral Damage。Filter / EQ 是一个用户可见模块族，通过 mode 参数覆盖 Low-pass、High-pass、Band-pass、Notch 和 Random Frequency Response；旧的单独 filter 类型如保留，只用于 Codable 迁移或开发数据解码，不应作为独立用户模块暴露。Low Quality Codec 和 Bitrate Reduction 应在 codec capability layer 明确后再实现。

## AudioPlaybackController

`AudioPlaybackController` 负责播放，不参与渲染。

职责：

- 手动播放原始 buffer。
- 手动播放处理后的 buffer。
- 停止当前播放。
- 保证同一时间只有一个源在播放。
- 不在导入、录音结束或渲染完成后自动播放。

实现可以从 `AVAudioPlayer` 或 `AVAudioEngine` + `AVAudioPlayerNode` 开始。无论采用哪种实现，自动化测试都不应点击播放按钮，也不应制造外放声音。

## Presets

v1 使用本地 JSON 存储预设。

预设类型：

- Module preset：保存单个 `EffectBlock` 的类型和参数。
- Workflow preset：保存完整 `Workflow`，包含有序 blocks 和每个 block 的参数。

规则：

- `Workflow`、`EffectBlock` 和 `EffectParameter` 必须 `Codable`。
- 预设存放在 App documents directory。
- `UserDefaults` 只用于轻量 UI 偏好，例如上次选择的模式或模块类型。
- v1 默认不持久化导入音频文件；用户音频按 session 导入或录制。
- 预设读取失败应返回可见错误，不能让 App 崩溃。

## Localization

所有用户可见文案必须进入 Xcode String Catalog：

```text
Deep-Fried Audio Player/Localizable.xcstrings
```

默认语言：

- 简体中文 `zh-Hans`
- 英文 `en`

本地化范围包括按钮、标题、空状态、错误、权限说明、模块名、参数名、单位标签和不可用 codec 状态。SwiftUI 视图应引用稳定语义 key，例如 `home.title`、`audio.import`、`mode.singleModule`、`workflow.addModule`。UI 测试应优先使用 accessibility identifier，不依赖某一种语言下的可见文本。

## Test Boundaries

自动化测试重点覆盖确定性逻辑，不触发外放播放。

单元测试边界：

- `AudioBuffer` 的基础不变量。
- `Workflow`、`EffectBlock`、`EffectParameter` 的 Codable round-trip。
- 空 workflow 返回原 buffer。
- disabled block 被旁路。
- block 重新排序会改变执行顺序。
- 参数变化会产生不同输出。
- processor 输出长度有效，且不包含 `NaN` 或 infinity。
- renderer 的安全限制让峰值保持在配置上限内。
- 预设保存和加载。

UI 测试边界：

- App 启动。
- Single Module Mode 与 Workflow Mode 切换。
- 生成示例音频。
- 添加模块。
- 修改参数。
- 观察处理状态变化。
- 确认 waveform 出现。
- 尽量验证用户可见文本来自 localization key 或对应 string catalog。

人工验收边界：

- 播放原音频和处理后音频。
- 听感确认 deep-fried 效果明显。
- 从 Files 导入真实音频。
- 麦克风录音和权限拒绝路径。
- iPhone 竖屏和 iPad 横屏体验。

## Non-Goals For v1

- 不为了 macOS 优化主架构。
- 不在 processor 中耦合 SwiftUI。
- 不在自动化测试中播放声音。
- 不把不可用 codec 伪装成真实支持。
- 不在 SwiftUI 层硬编码长用户文案。
