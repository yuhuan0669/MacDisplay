# MacDisplay

MacDisplay 是一个基于 macOS 原生图形与视频硬件加速体系（CoreGraphics + VideoToolbox + Network framework）实现的超低延迟、局域网高清屏幕投屏与**虚拟扩展副屏**系统。

专为两台 Mac 间（例如：MacBook 投屏至 27寸 5K iMac）提供接近硬件直连级、满血 60 FPS 的无线扩展显示与镜像体验而设计。

---

## 核心特性

- **🖥️ 原生 16:9 虚拟独立扩展副屏（真副屏办公）**
  - **私有框架深度集成**：基于 `CGVirtualDisplay` 驱动，在系统内核动态创建原生的 2560×1440 @ 60Hz 独立显示器。
  - **16:9 物理比例适配**：完美契合 iMac 27寸 屏幕比例，彻底消除上下黑边与模糊拉伸，文字边缘锐利无锯齿。
  - **双模式无缝切换**：支持“🖥️ 扩展副屏模式”与“🪞 镜像屏模式”一键热切换。
  - **原生窗口与输入聚焦**：全屏模式下，鼠标从 MacBook 屏幕边缘滑入副屏，直接拖拽窗口、选中文本、键入内容，与连接物理外接显示器体验完全一致。

- **⚡️ 满血 60 FPS HEVC (H.265) 硬件超清编解码管线**
  - **硬件级零延迟编码（ZeroDelay）**：MacBook 启用 Apple Silicon VideoToolbox 硬编码器，禁用帧重排（No B-frames），单帧编码耗时仅 1~2ms。
  - **26 Mbps 视网膜级码率**：为 2.5K 桌面文本定制高动态码率与高保真色彩配置，快速滚屏无马赛克，小号文字极度清晰。
  - **iMac 极速硬件解码**：完美调动 iMac（Intel QuickSync / AMD Radeon Pro）固定功能硬件解码器，单帧解码耗时仅 3~4ms，解码丢帧率为 0。

- **🎯 单调递增 20ms VSYNC 帧步进引擎（彻底解决鼠标瞬移与丢帧）**
  - **告别中间帧驱逐（Anti-Eviction）**：彻底剔除传统即时投屏中 `DisplayImmediately` 导致显卡队列丢弃 75% 动画帧的致命缺陷。
  - **精密时钟超前锁（20ms VSYNC Lead）**：每一帧严格根据当前宿主时钟赋予单调递增的未来 20ms PTS，让画面每一帧在到达显示器垂直消隐（VBLANK）前精准就绪。
  - **物理 60.0 FPS 稳定上屏**：单帧在屏显示时长稳定恒定在 **`16.669 ms`**，鼠标移动呈现连贯自然的物理轨迹。

- **🚀 端到端微秒级极速直通**
  - **队列零堆积**：设置 `kCGDisplayStreamQueueDepth: 1` 与 `kCGDisplayStreamMinimumFrameTime: 0.0`，消除 CoreGraphics 捕获缓冲和刷新率别名丢帧。
  - **TCP 立即推送**：全面采用 Network.framework `.contentProcessed` 即时分发，彻底消除系统内核网络用户态缓冲。
  - **自动发现与局域网直连**：支持 Bonjour 服务发现与局域网直连双通道，瞬间建立连接。

- **🎨 现代化交互与控制**
  - **Sender 端**：
    - 常驻菜单栏图标 `🖥️`，支持快速切换模式、查看客户端连接与一键暂停/恢复。
    - 屏幕录制权限预检引导。
  - **Receiver 端**：
    - `Cmd + F` / `Esc`：一键全屏 / 窗口化切换。
    - `Cmd + 1`：等比例居中（保留原始画面比例）。
    - `Cmd + 2`：填满屏幕（拉伸全屏）。
    - `Cmd + Q`：退出应用。
    - 右上角半透明悬浮胶囊控制栏：支持一键切换画面比例及退出。

---

## 项目架构

```
MacDisplay/
├── Package.swift                       # SwiftPM 模块依赖配置
├── Sources/
│   ├── Shared/
│   │   └── Transport.swift             # 二进制传输协议、网络帧封包与 Socket 通信
│   ├── VirtualDisplayBridge/           # Objective-C 桥接层
│   │   ├── VirtualDisplayBridge.m      # 私有 CGVirtualDisplay 虚拟显示器动态加载与生命周期管理
│   │   └── include/
│   │       └── VirtualDisplayBridge.h  # 虚拟显示器头文件定义
│   ├── Sender/
│   │   └── main.swift                  # 发送端：CGDisplayStream捕获、HEVC硬件编码、状态菜单栏与浮窗
│   └── Receiver/
│       └── main.swift                  # 接收端：AVSampleBufferDisplayLayer直出、20ms VSYNC 帧步进引擎与全屏交互
└── scripts/
    └── package_apps.sh                 # 一键编译、打包签名独立 macOS .app 脚本
```

---

## 快速编译与运行

### 推荐：一键打包为双击运行的独立 `.app`

在项目根目录下执行打包脚本：
```bash
./scripts/package_apps.sh
```

生成后的应用位于 `dist/` 目录：
- **`dist/MacDisplay Sender.app`**：
  复制至发送端 Mac（如 MacBook），双击启动。首次启动时根据提示在“系统设置 -> 隐私与安全性 -> 屏幕录制”中授权。
- **`dist/MacDisplay Receiver.app`**：
  复制至接收端 Mac（如 iMac），双击启动即可全屏进入待命，自动连接局域网内的 MacBook。

---

### 高级：通过 SwiftPM 命令行运行

1. **编译发布版本**：
   ```bash
   swift build -c release
   ```

2. **在发射端 Mac（如 MacBook）运行**：
   ```bash
   swift run -c release Sender
   ```

3. **在接收端 Mac（如 iMac）运行**：
   ```bash
   swift run -c release Receiver
   ```

---

## 系统要求

- **发射端**：macOS 13.0 (Ventura) 及以上，推荐 Apple Silicon (M1/M2/M3/M4/M5 系列)
- **接收端**：macOS 12.0 (Monterey) 及以上，推荐 2017+ iMac 5K（配备 AMD Radeon Pro 或 Intel 核显）或任意 Mac
- **网络环境**：建议在同一局域网下使用（推荐 5GHz Wi-Fi 或千兆有线网络连接）

---

## License

MIT License
