# MacDisplay

MacDisplay 是一个基于 macOS 原生图形与视频硬编解码框架（CoreGraphics + VideoToolbox + Network framework）实现的超低延迟、局域网高清屏幕投屏与镜像系统。

专为两台 Mac 间（例如：MacBook 投屏至 5K 27寸 iMac 作为副屏或扩展显示）提供接近原生无感的投屏体验而设计。

---

## 核心特性

- **极致低延迟与原生画质**
  - **原生 Retina 捕获**：支持 3024×1964 @ 30fps（根据显示器自动适配最高分辨率）。
  - **硬件加速编解码**：使用 Apple Silicon / VideoToolbox 硬件 H.264 编码器，启用 CABAC 熵编码与低延迟实时编码模式。
  - **抗画质劣化**：设置 50 Mbps 峰值码率与最大 QP 阈值（`MaxAllowedFrameQP = 28`），并在快速动态画面下保障清晰度，消除色块与马赛克。
  - **鼠标光标同屏采集**：硬件级光标捕捉（`kCGDisplayStreamShowCursor`），本机移动鼠标在接收端平滑实时显示。

- **高可靠性 AVCC 传输协议**
  - 使用帧头定制的二进制协议，SPS/PPS 参数集带外同步传输（`MSG_FORMAT`）。
  - 支持连接自动重连与优雅断开，无内存泄漏与死锁。

- **现代化交互界面**
  - **Sender 端**：
    - 常驻菜单栏图标（状态与 IP 地址显示）。
    - 屏幕顶部半透明悬浮控制胶囊，实时显示连接状态，支持一键断开或退出。
    - 权限预检（自动提示并引导开启屏幕录制权限）。
  - **Receiver 端**：
    - 硬件级图层直出（`AVSampleBufferDisplayLayer`）。
    - 快捷键支持：
      - `Cmd + F` / `Esc`：全屏 / 窗口化切换。
      - `Cmd + 1`：等比例居中（保持 16:10，两侧留黑边）。
      - `Cmd + 2`：拉伸充满全屏（16:9 铺满整个 iMac 5K 屏幕）。
      - `Cmd + Q`：退出应用。
    - 右上角悬浮智能控制栏：直接点击 `[填满屏幕]` / `[等比居中]` 切换显示模式，点击 `[✕]` 快速退出。
    - 支持右键呼出快捷菜单。

---

## 项目架构

```
MacDisplay/
├── Package.swift               # SwiftPM 配置文件
├── Sources/
│   ├── Shared/
│   │   └── Transport.swift     # 二进制通信协议与 Socket 封装
│   ├── Sender/
│   │   └── main.swift          # 发送端：屏幕捕获、硬编码与控制浮窗
│   └── Receiver/
│       └── main.swift          # 接收端：硬解渲染、窗口控制与缩放切换
└── scripts/
    └── package_apps.sh         # 一键打包成 macOS .app 脚本
```

---

## 快速编译与运行

### 方式 1：通过 SwiftPM 命令行运行

1. **编译全部目标**：
   ```bash
   swift build -c release
   ```

2. **在发射端 Mac（如 MacBook）运行**：
   ```bash
   swift run -c release Sender [PORT]
   # 默认端口为 7892
   ```

3. **在接收端 Mac（如 iMac）运行**：
   ```bash
   swift run -c release Receiver <SENDER_IP> [PORT]
   # 例如：swift run -c release Receiver 10.140.2.206 7892
   ```

---

### 方式 2：打包为双击运行的独立 `.app`

在项目根目录下运行打包脚本：
```bash
./scripts/package_apps.sh
```

生成后的应用位于 `dist/` 目录：
- `dist/MacDisplay Sender.app`：双击即可启动发送端，初次启动时系统会引导赋予“屏幕录制”权限。
- `dist/MacDisplay Receiver.app`：双击即可连接并显示投屏画面。

---

## 系统要求

- macOS 13.0 (Ventura) 及以上
- 推荐使用 Apple Silicon (M1/M2/M3/M4) 或支持 Intel QuickSync 的 Mac
- 局域网千兆 Wi-Fi 或有线网络连接（推荐 5GHz Wi-Fi 或网线直连）

---

## License

MIT License
