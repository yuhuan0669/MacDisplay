import Foundation
import CoreGraphics
import CoreVideo
import VideoToolbox
import CoreMedia
import Network
import AppKit
import Shared
import VirtualDisplayBridge

// MARK: - Display Mode
enum DisplayMode: String {
    case extended = "extended" // iMac 独立副屏 (16:9 无黑边)
    case mirror   = "mirror"   // 克隆 MacBook 屏幕
}

private var currentDisplayMode: DisplayMode = .extended

// MARK: - App Delegate & Controller
class SenderAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var controlWindow: NSWindow!
    var statusLabel: NSTextField!
    var infoLabel: NSTextField!
    var clientLabel: NSTextField!
    var modeSegment: NSSegmentedControl!
    var toggleButton: NSButton!
    var isStreaming = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupControlWindow()
        startServer()

        if !CGPreflightScreenCaptureAccess() {
            print("Screen capture permission missing. Prompting user...")
            CGRequestScreenCaptureAccess()
            showPermissionRequiredUI()
        } else {
            startCapture()
            updateUI()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopCapture()
        VirtualDisplayManager.shared().destroyVirtualDisplay()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🖥️"
            button.toolTip = "MacDisplay Sender"
        }
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "MacDisplay Sender: 运行中", action: nil, keyEquivalent: "")
        titleItem.tag = 100
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let extItem = NSMenuItem(title: "🖥️ 扩展屏模式 (iMac 独立副屏 16:9)", action: #selector(selectExtendedMode), keyEquivalent: "e")
        extItem.tag = 201
        menu.addItem(extItem)

        let mirItem = NSMenuItem(title: "🪞 镜像屏模式 (克隆 MacBook 桌面)", action: #selector(selectMirrorMode), keyEquivalent: "m")
        mirItem.tag = 202
        menu.addItem(mirItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "显示控制面板…", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "暂停 / 继续投屏", action: #selector(toggleStreaming), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 MacDisplay", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func selectExtendedMode() {
        setMode(.extended)
    }

    @objc func selectMirrorMode() {
        setMode(.mirror)
    }

    func setupControlWindow() {
        let frame = NSRect(x: 200, y: 300, width: 380, height: 260)
        controlWindow = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        controlWindow.title = "MacDisplay 投屏控制"
        controlWindow.isReleasedWhenClosed = false
        controlWindow.center()

        let cv = NSView(frame: controlWindow.contentView!.bounds)
        cv.autoresizingMask = [.width, .height]

        // Status badge
        statusLabel = NSTextField(labelWithString: "● 正在投屏 (HEVC 黄金平衡 / 20Mbps)")
        statusLabel.textColor = .systemGreen
        statusLabel.font = .systemFont(ofSize: 15, weight: .bold)
        statusLabel.frame = NSRect(x: 20, y: 215, width: 340, height: 24)
        cv.addSubview(statusLabel)

        // Mode switch
        let modeTitle = NSTextField(labelWithString: "显示模式:")
        modeTitle.font = .systemFont(ofSize: 13, weight: .medium)
        modeTitle.frame = NSRect(x: 20, y: 178, width: 70, height: 22)
        cv.addSubview(modeTitle)

        modeSegment = NSSegmentedControl(labels: ["🖥️ 扩展屏 (独立副屏)", "🪞 镜像 (克隆屏)"],
                                         trackingMode: .selectOne,
                                         target: self,
                                         action: #selector(modeSegmentChanged(_:)))
        modeSegment.frame = NSRect(x: 95, y: 174, width: 265, height: 28)
        modeSegment.selectedSegment = (currentDisplayMode == .extended) ? 0 : 1
        cv.addSubview(modeSegment)

        // Details
        infoLabel = NSTextField(labelWithString: "分辨率: 2560×1440 (16:9 无黑边)\n编解码: HEVC (H.265 硬件加速 20Mbps)")
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.frame = NSRect(x: 20, y: 115, width: 340, height: 42)
        cv.addSubview(infoLabel)

        clientLabel = NSTextField(labelWithString: "接收设备: 等待连接…")
        clientLabel.textColor = .labelColor
        clientLabel.font = .systemFont(ofSize: 13, weight: .medium)
        clientLabel.frame = NSRect(x: 20, y: 75, width: 340, height: 22)
        cv.addSubview(clientLabel)

        // Action Buttons
        toggleButton = NSButton(title: "暂停投屏", target: self, action: #selector(toggleStreaming))
        toggleButton.bezelStyle = .rounded
        toggleButton.frame = NSRect(x: 18, y: 20, width: 160, height: 36)
        cv.addSubview(toggleButton)

        let quitBtn = NSButton(title: "退出投屏", target: self, action: #selector(quitApp))
        quitBtn.bezelStyle = .rounded
        quitBtn.frame = NSRect(x: 202, y: 20, width: 160, height: 36)
        cv.addSubview(quitBtn)

        controlWindow.contentView = cv
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func modeSegmentChanged(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            setMode(.extended)
        } else {
            setMode(.mirror)
        }
    }

    func showPermissionRequiredUI() {
        statusLabel.stringValue = "⚠️ 缺少屏幕录制权限"
        statusLabel.textColor = .systemRed
        clientLabel.stringValue = "设置中开启后若有弹窗，请点击【退出并重新打开】"
        clientLabel.textColor = .systemRed
        toggleButton.title = "去设置开启权限"
        toggleButton.action = #selector(openScreenRecordingSettings)
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        // Check periodically if granted
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if CGPreflightScreenCaptureAccess() {
                timer.invalidate()
                self?.toggleButton.action = #selector(self?.toggleStreaming)
                startCapture()
                self?.updateUI()
            }
        }
    }

    @objc func showWindow() {
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleStreaming() {
        isStreaming.toggle()
        if isStreaming {
            startCapture()
            needKeyframe = true
        } else {
            stopCapture()
        }
        updateUI()
    }

    @objc func quitApp() {
        stopCapture()
        VirtualDisplayManager.shared().destroyVirtualDisplay()
        NSApp.terminate(nil)
    }

    func updateUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let count: Int
            clientsLock.lock()
            count = clients.count
            clientsLock.unlock()

            if self.isStreaming {
                self.statusLabel.stringValue = "● 正在投屏 (HEVC 视网膜清晰 / 26Mbps)"
                self.statusLabel.textColor = .systemGreen
                self.toggleButton.title = "暂停投屏"
                if let item = self.statusItem.menu?.item(withTag: 100) {
                    item.title = "MacDisplay: 正在投屏 (\(count)台设备)"
                }
            } else {
                self.statusLabel.stringValue = "⏸ 投屏已暂停"
                self.statusLabel.textColor = .systemOrange
                self.toggleButton.title = "恢复投屏"
                if let item = self.statusItem.menu?.item(withTag: 100) {
                    item.title = "MacDisplay: 已暂停"
                }
            }

            if count > 0 {
                self.clientLabel.stringValue = "接收设备: 已连接 \(count) 台 (iMac)"
                self.clientLabel.textColor = .systemBlue
            } else {
                self.clientLabel.stringValue = "接收设备: 等待 iMac 连接…"
                self.clientLabel.textColor = .secondaryLabelColor
            }

            if currentDisplayMode == .extended {
                self.infoLabel.stringValue = "模式: 🖥️ 扩展屏 (16:9 铺满 iMac, 零黑边)\n分辨率: \(capturedWidth)×\(capturedHeight) @ 60fps (HEVC 26Mbps)"
                self.modeSegment.selectedSegment = 0
            } else {
                self.infoLabel.stringValue = "模式: 🪞 镜像屏 (克隆 MacBook 桌面)\n分辨率: \(capturedWidth)×\(capturedHeight) @ 60fps (HEVC 26Mbps)"
                self.modeSegment.selectedSegment = 1
            }

            if let extItem = self.statusItem.menu?.item(withTag: 201) {
                extItem.state = (currentDisplayMode == .extended) ? .on : .off
            }
            if let mirItem = self.statusItem.menu?.item(withTag: 202) {
                mirItem.state = (currentDisplayMode == .mirror) ? .on : .off
            }
        }
    }
}

// MARK: - Globals
private var appDelegate = SenderAppDelegate()
private var clients: [FramedConnection] = []
private let clientsLock = NSLock()
private var encoderSession: VTCompressionSession?
private var frameIndex: Int64 = 0
private var displayStream: CGDisplayStream?
private var capturedWidth  = 0
private var capturedHeight = 0
private var needKeyframe   = false
private var lastFormatData: Data?

// MARK: - Entry Point
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = appDelegate
app.run()

// MARK: - Bonjour Server
func startServer() {
    guard let listener = try? NWListener(using: makeLowLatencyTCPParameters(), on: 7892) else {
        print("Failed to create listener"); return
    }
    listener.service = NWListener.Service(type: kServiceType)
    listener.newConnectionHandler = { conn in
        print("Client connected: \(conn.endpoint)")
        fflush(stdout)
        let fc = FramedConnection(conn)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Client connection ready: \(conn.endpoint)")
                fflush(stdout)
                let cfg = DisplayConfig(width: UInt32(capturedWidth),
                                        height: UInt32(capturedHeight), fps: 60)
                fc.send(type: MSG_CONFIG, payload: cfg.data)

                clientsLock.lock()
                let fmt = lastFormatData
                clientsLock.unlock()
                if let f = fmt {
                    fc.send(type: MSG_FORMAT, payload: f)
                }
                needKeyframe = true
            case .cancelled, .failed:
                clientsLock.lock()
                clients.removeAll { $0 === fc }
                clientsLock.unlock()
                print("Client disconnected: \(state)")
                fflush(stdout)
                appDelegate.updateUI()
            default: break
            }
        }
        conn.start(queue: .global())

        clientsLock.lock()
        clients.append(fc)
        clientsLock.unlock()
        needKeyframe = true
        appDelegate.updateUI()
    }
    listener.stateUpdateHandler = { state in
        if case .ready = state {
            print("Listening on port 7892, Bonjour: \(kServiceType)")
        }
    }
    listener.start(queue: .global())
}

func setMode(_ mode: DisplayMode) {
    guard mode != currentDisplayMode else { return }
    print("Switching display mode from \(currentDisplayMode.rawValue) to: \(mode.rawValue)")
    stopCapture()

    currentDisplayMode = mode

    if mode == .extended {
        let ok = VirtualDisplayManager.shared().createVirtualDisplay(
            withWidth: 2560,
            height: 1440,
            hiDPI: false,
            name: "iMac 5K 扩展显示器"
        )
        print("createVirtualDisplay returned: \(ok)")
        // Give WindowServer 0.4s to stabilize before starting capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            startCapture()
            needKeyframe = true
            appDelegate.updateUI()
        }
    } else {
        VirtualDisplayManager.shared().destroyVirtualDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            startCapture()
            needKeyframe = true
            appDelegate.updateUI()
        }
    }
}

// MARK: - Capture
func startCapture() {
    guard displayStream == nil else { return }
    guard CGPreflightScreenCaptureAccess() else {
        print("Screen capture permission not granted yet")
        DispatchQueue.main.async {
            appDelegate.showPermissionRequiredUI()
        }
        return
    }

    var targetDisplayID: CGDirectDisplayID = CGMainDisplayID()

    if currentDisplayMode == .extended {
        let vdm = VirtualDisplayManager.shared()
        if !vdm.isRunning {
            _ = vdm.createVirtualDisplay(withWidth: 2560, height: 1440, hiDPI: false, name: "iMac 5K 扩展显示器")
        }
        targetDisplayID = vdm.displayID
        capturedWidth = vdm.activeWidth > 0 ? Int(vdm.activeWidth) : 2560
        capturedHeight = vdm.activeHeight > 0 ? Int(vdm.activeHeight) : 1440
    } else {
        targetDisplayID = CGMainDisplayID()
        if let mode = CGDisplayCopyDisplayMode(targetDisplayID) {
            capturedWidth  = mode.pixelWidth
            capturedHeight = mode.pixelHeight
        } else {
            capturedWidth  = CGDisplayPixelsWide(targetDisplayID) * 2
            capturedHeight = CGDisplayPixelsHigh(targetDisplayID) * 2
        }
    }

    // Safety fallback: ensure width and height are never 0
    if capturedWidth <= 0 { capturedWidth = 2560 }
    if capturedHeight <= 0 { capturedHeight = 1440 }
    capturedWidth  -= (capturedWidth % 2)
    capturedHeight -= (capturedHeight % 2)
    print("Capturing Display \(targetDisplayID): \(capturedWidth)×\(capturedHeight) (Mode: \(currentDisplayMode.rawValue))")

    if let session = encoderSession {
        VTCompressionSessionInvalidate(session)
        encoderSession = nil
    }
    setupEncoder(width: capturedWidth, height: capturedHeight)

    // Notify connected clients of current display size
    let cfg = DisplayConfig(width: UInt32(capturedWidth),
                            height: UInt32(capturedHeight), fps: 60)
    clientsLock.lock()
    let snapshot = clients
    clientsLock.unlock()
    snapshot.forEach { $0.send(type: MSG_CONFIG, payload: cfg.data) }

    let props: [AnyHashable: Any] = [
        "kCGDisplayStreamMinimumFrameTime": NSNumber(value: 0.0), // 0.0: pass every frame instantly without artificial timing suppression
        "kCGDisplayStreamShowCursor": kCFBooleanTrue as Any,
        "kCGDisplayStreamQueueDepth": NSNumber(value: 1) // Critical: 1 frame queue depth eliminates 33-50ms buffering!
    ]
    displayStream = CGDisplayStream(
        dispatchQueueDisplay: targetDisplayID,
        outputWidth:  capturedWidth,
        outputHeight: capturedHeight,
        pixelFormat:  Int32(kCVPixelFormatType_32BGRA),
        properties:   props as CFDictionary,
        queue: DispatchQueue(label: "capture", qos: .userInteractive)
    ) { status, _, ioSurface, _ in
        guard status == .frameComplete, let surface = ioSurface else { return }
        encodeFrame(surface: surface)
    }
    guard let ds = displayStream else {
        print("CGDisplayStream creation returned nil for display \(targetDisplayID)")
        return
    }
    guard ds.start() == .success else {
        print("CGDisplayStream start failed for display \(targetDisplayID)")
        return
    }
    print("Capture started on Display \(targetDisplayID) (60 FPS, QueueDepth=1, Embedded Cursor)")
}

func stopCapture() {
    displayStream?.stop()
    displayStream = nil
    print("Capture stopped")
}

// MARK: - Encoder Setup
func setupEncoder(width: Int, height: Int) {
    guard width > 0 && height > 0 else {
        print("Invalid encoder dimensions: \(width)x\(height)")
        return
    }

    var session: VTCompressionSession?
    let bitrate = 26_000_000 // 26 Mbps HEVC: crystal-clear text & ultra-low latency for 2560x1440 on LAN

    let cb: VTCompressionOutputCallback = { _, _, status, _, sampleBuffer in
        guard status == noErr, let sb = sampleBuffer else { return }
        broadcastFrame(sampleBuffer: sb)
    }
    let encoderSpec: [CFString: Any] = [
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any,
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any
    ]
    let err = VTCompressionSessionCreate(
        allocator: nil,
        width: Int32(width), height: Int32(height),
        codecType: kCMVideoCodecType_HEVC,
        encoderSpecification: encoderSpec as CFDictionary,
        imageBufferAttributes: nil,
        compressedDataAllocator: nil,
        outputCallback: cb,
        refcon: nil,
        compressionSessionOut: &session
    )
    guard err == noErr, let s = session else {
        print("HEVC Encoder create failed: \(err)")
        return
    }

    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime,             value: kCFBooleanTrue)
    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxFrameDelayCount,   value: 0 as CFNumber)
    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,         value: kVTProfileLevel_HEVC_Main_AutoLevel)
    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate,       value: bitrate as CFNumber)
    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_Quality,              value: 0.95 as CFNumber)
    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate,    value: NSNumber(value: 60))
    VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,  value: NSNumber(value: 60))
    VTCompressionSessionPrepareToEncodeFrames(s)
    encoderSession = s
    print("HEVC Hardware Encoder ready (\(width)x\(height), \(bitrate / 1_000_000) Mbps, ZeroDelay, 60 FPS, KeyInterval: 60 frames)")
}

// MARK: - Per-Frame Encode
private var debugFrameCount: Int = 0
private var debugLastSec: Double = 0

func encodeFrame(surface: IOSurface) {
    guard let session = encoderSession else { return }

    debugFrameCount += 1
    let now = Date().timeIntervalSinceReferenceDate
    if now - debugLastSec >= 1.0 {
        let fps = Double(debugFrameCount) / (now - debugLastSec)
        print("[Sender FPS] Capturing & encoding at \(String(format: "%.1f", fps)) FPS")
        fflush(stdout)
        debugFrameCount = 0
        debugLastSec = now
    }

    var unmanagedPB: Unmanaged<CVPixelBuffer>?
    let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
    let cvErr = CVPixelBufferCreateWithIOSurface(nil, surface, attrs, &unmanagedPB)
    guard cvErr == kCVReturnSuccess, let pixelBuffer = unmanagedPB?.takeRetainedValue() else { return }

    let pts = CMTimeMake(value: frameIndex, timescale: 60)
    frameIndex += 1
    var frameProps: CFDictionary? = nil
    if needKeyframe {
        frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
        needKeyframe = false
    }
    VTCompressionSessionEncodeFrame(
        session, imageBuffer: pixelBuffer,
        presentationTimeStamp: pts, duration: .invalid,
        frameProperties: frameProps, sourceFrameRefcon: nil, infoFlagsOut: nil
    )
}

// MARK: - Broadcast
func broadcastFrame(sampleBuffer: CMSampleBuffer) {
    guard let blockBuf = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    let totalLen = CMBlockBufferGetDataLength(blockBuf)
    guard totalLen > 0 else { return }

    let keyframe = isKeyframe(sampleBuffer)
    if (keyframe || lastFormatData == nil),
       let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
       let psData = extractParameterSets(fmt) {
        lastFormatData = psData
        clientsLock.lock()
        let snapshot = clients
        clientsLock.unlock()
        snapshot.forEach { $0.send(type: MSG_FORMAT, payload: psData) }
    }

    var frameData = Data(count: totalLen)
    _ = frameData.withUnsafeMutableBytes { ptr in
        CMBlockBufferCopyDataBytes(blockBuf, atOffset: 0, dataLength: totalLen, destination: ptr.baseAddress!)
    }

    // Embed 8-byte millisecond timestamp at the beginning of payload
    var videoPayload = Data(capacity: 8 + totalLen)
    var nowMs = UInt64(Date().timeIntervalSince1970 * 1000).littleEndian
    withUnsafeBytes(of: &nowMs) { videoPayload.append(contentsOf: $0) }
    videoPayload.append(frameData)

    clientsLock.lock()
    let snapshot = clients
    clientsLock.unlock()

    for client in snapshot {
        client.send(type: MSG_VIDEO, payload: videoPayload)
    }
}

func isKeyframe(_ sb: CMSampleBuffer) -> Bool {
    guard let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false),
          CFArrayGetCount(arr) > 0 else { return true }
    let rawDict = CFArrayGetValueAtIndex(arr, 0)
    let dict = unsafeBitCast(rawDict, to: CFDictionary.self)
    return !CFDictionaryContainsKey(dict, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
}

func extractParameterSets(_ fmt: CMVideoFormatDescription) -> Data? {
    var count = 0
    let err = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
        fmt, parameterSetIndex: 0,
        parameterSetPointerOut: nil, parameterSetSizeOut: nil,
        parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil
    )
    guard err == noErr, count > 0 else { return nil }

    var d = Data()
    d.append(UInt8(count))
    for i in 0..<count {
        var ptr: UnsafePointer<UInt8>?
        var size = 0
        let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            fmt, parameterSetIndex: i,
            parameterSetPointerOut: &ptr, parameterSetSizeOut: &size,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
        )
        guard status == noErr, let p = ptr, size > 0 else { return nil }
        var sLen = UInt16(size).littleEndian
        withUnsafeBytes(of: &sLen) { d.append(contentsOf: $0) }
        d.append(p, count: size)
    }
    return d
}
