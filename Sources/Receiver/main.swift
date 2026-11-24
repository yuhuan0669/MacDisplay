import Foundation
import Network
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox
import AppKit
import Shared

// MARK: - App Entry
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - Interactive Video View
class VideoContainerView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()
    var floatingBar: NSView!
    var floatingScaleBtn: NSButton!
    var floatingCloseBtn: NSButton!
    var isStretched = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        displayLayer.frame = bounds
        displayLayer.videoGravity = .resizeAspect
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(displayLayer)

        setupFloatingControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setupFloatingControls() {
        floatingBar = NSView(frame: NSRect(x: bounds.width - 180, y: bounds.height - 50, width: 165, height: 38))
        floatingBar.autoresizingMask = [.minXMargin, .minYMargin]
        floatingBar.wantsLayer = true
        floatingBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        floatingBar.layer?.cornerRadius = 19
        floatingBar.layer?.masksToBounds = true

        floatingScaleBtn = NSButton(title: "填满屏幕", target: self, action: #selector(toggleScaleMode))
        floatingScaleBtn.bezelStyle = .inline
        floatingScaleBtn.font = .systemFont(ofSize: 12, weight: .medium)
        floatingScaleBtn.frame = NSRect(x: 10, y: 5, width: 70, height: 28)
        floatingBar.addSubview(floatingScaleBtn)

        floatingCloseBtn = NSButton(title: "退出 ✕", target: self, action: #selector(closeApp))
        floatingCloseBtn.bezelStyle = .inline
        floatingCloseBtn.font = .systemFont(ofSize: 12, weight: .medium)
        floatingCloseBtn.frame = NSRect(x: 88, y: 5, width: 68, height: 28)
        floatingBar.addSubview(floatingCloseBtn)

        addSubview(floatingBar)
    }

    @objc func closeApp() {
        NSApp.terminate(nil)
    }

    @objc func toggleScaleMode() {
        isStretched.toggle()
        if isStretched {
            displayLayer.videoGravity = .resize
            floatingScaleBtn.title = "等比居中"
        } else {
            displayLayer.videoGravity = .resizeAspect
            floatingScaleBtn.title = "填满屏幕"
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: isStretched ? "✓ 画面比例: 充满屏幕 (拉伸)" : "画面比例: 充满屏幕 (拉伸)", action: #selector(setStretch), keyEquivalent: "2"))
        menu.addItem(NSMenuItem(title: !isStretched ? "✓ 画面比例: 等比居中 (清晰推荐)" : "画面比例: 等比居中 (清晰推荐)", action: #selector(setAspect), keyEquivalent: "1"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "切换全屏 / 窗口", action: #selector(toggleFullScreen), keyEquivalent: "f"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 MacDisplay", action: #selector(closeApp), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func setAspect() {
        isStretched = false
        displayLayer.videoGravity = .resizeAspect
        floatingScaleBtn.title = "填满屏幕"
    }

    @objc func setStretch() {
        isStretched = true
        displayLayer.videoGravity = .resize
        floatingScaleBtn.title = "等比居中"
    }

    @objc func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }
}

// MARK: - Key-Handling Window
class ReceiverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Esc (keyCode 53) -> exit fullscreen
        if event.keyCode == 53 {
            if styleMask.contains(.fullScreen) {
                toggleFullScreen(nil)
                return
            }
        }
        // Cmd + F -> toggle fullscreen
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            toggleFullScreen(nil)
            return
        }
        // Cmd + Q -> quit
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return
        }
        // Cmd + 1 -> aspect
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "1" {
            if let view = contentView as? VideoContainerView {
                view.setAspect()
            }
            return
        }
        // Cmd + 2 -> stretch
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "2" {
            if let view = contentView as? VideoContainerView {
                view.setStretch()
            }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: ReceiverWindow!
    var videoView: VideoContainerView!
    var client: DisplayClient!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupWindow()
        client = DisplayClient(layer: videoView.displayLayer)
        client.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出 MacDisplay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "视图")
        viewMenu.addItem(NSMenuItem(title: "切换全屏", action: #selector(toggleFullScreen), keyEquivalent: "f"))
        viewMenu.addItem(NSMenuItem(title: "等比居中 (清晰)", action: #selector(setAspect), keyEquivalent: "1"))
        viewMenu.addItem(NSMenuItem(title: "充满屏幕 (拉伸)", action: #selector(setStretch), keyEquivalent: "2"))
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    @objc func toggleFullScreen() { window.toggleFullScreen(nil) }
    @objc func setAspect() { videoView.setAspect() }
    @objc func setStretch() { videoView.setStretch() }

    func setupWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame  = screen.frame

        window = ReceiverWindow(
            contentRect: NSRect(x: 100, y: 100, width: frame.width * 0.85, height: frame.height * 0.85),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        window.delegate = self
        window.title = "MacDisplay Receiver"
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()

        videoView = VideoContainerView(frame: window.contentView!.bounds)
        videoView.autoresizingMask = [.width, .height]
        window.contentView = videoView

        // Status label
        let label = NSTextField(labelWithString: "正在连接 MacDisplay Sender…")
        label.textColor = .white
        label.font      = .systemFont(ofSize: 20, weight: .medium)
        label.frame     = NSRect(x: 0, y: videoView.bounds.height/2 - 25, width: videoView.bounds.width, height: 50)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.tag       = 999
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        videoView.addSubview(label)

        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

// MARK: - Network Client
class DisplayClient {
    private let layer: AVSampleBufferDisplayLayer
    private var browser: NWBrowser?
    private var framed: FramedConnection?
    private var formatDesc: CMVideoFormatDescription?
    private var frameCount: Int64 = 0
    private var minLatencyMs: Int64 = Int64.max
    private var lastLatencyResetTime: Double = 0

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }

    func start() {
        let params = makeLowLatencyTCPParameters()
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: kServiceType, domain: kServiceDomain), using: params)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self, self.framed == nil else { return }
            if let result = results.first {
                print("Discovered Bonjour service: \(result.endpoint)")
                fflush(stdout)
                self.connect(to: result.endpoint)
            }
        }
        browser?.stateUpdateHandler = { state in
            print("Browser: \(state)")
            fflush(stdout)
        }
        browser?.start(queue: .global())
        print("Browsing for \(kServiceType)…")
        fflush(stdout)

        // Fallback: direct connection if Bonjour takes > 1.0s
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.framed == nil else { return }
            print("Direct fallback: connecting to 10.140.2.206:7892...")
            fflush(stdout)
            self.connect(to: NWEndpoint.hostPort(host: "10.140.2.206", port: 7892))
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        guard framed == nil else { return }
        print("Connecting to \(endpoint)")
        fflush(stdout)
        let conn = NWConnection(to: endpoint, using: makeLowLatencyTCPParameters())
        framed = FramedConnection(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connected to \(endpoint)!")
                fflush(stdout)
                DispatchQueue.main.async {
                    if let win = NSApplication.shared.windows.first,
                       let view = win.contentView,
                       let label = view.viewWithTag(999) {
                        label.removeFromSuperview()
                    }
                }
                self?.framed?.startReceiving(handler: { type, payload in
                    self?.handle(type: type, payload: payload)
                })
            case .failed(let err):
                print("Connection failed: \(err)")
                fflush(stdout)
                self?.cleanupAndRestart()
            case .cancelled:
                print("Connection cancelled")
                fflush(stdout)
                self?.cleanupAndRestart()
            default: break
            }
        }
        conn.start(queue: .global())
    }

    private func cleanupAndRestart() {
        framed = nil
        formatDesc = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.start()
        }
    }

    private func handle(type: UInt8, payload: Data) {
        switch type {
        case MSG_CONFIG:
            guard let cfg = DisplayConfig(data: payload) else { return }
            print("Config: \(cfg.width)×\(cfg.height) @\(cfg.fps)fps")
            fflush(stdout)
        case MSG_FORMAT:
            handleFormat(payload)
        case MSG_VIDEO:
            handleVideo(payload)
        default:
            break
        }
    }

    private func handleFormat(_ payload: Data) {
        guard payload.count >= 4 else { return }
        let s0 = payload[payload.startIndex]
        let s1 = payload[payload.startIndex + 1]
        let sLen = Int(UInt16(s0) | (UInt16(s1) << 8))

        guard payload.count >= 4 + sLen else { return }
        let p0 = payload[payload.startIndex + 2 + sLen]
        let p1 = payload[payload.startIndex + 3 + sLen]
        let pLen = Int(UInt16(p0) | (UInt16(p1) << 8))

        guard payload.count >= 4 + sLen + pLen else { return }
        let spsStart = payload.startIndex + 2
        let spsEnd = spsStart + sLen
        let ppsStart = payload.startIndex + 4 + sLen
        let ppsEnd = ppsStart + pLen

        let spsData = payload.subdata(in: spsStart ..< spsEnd)
        let ppsData = payload.subdata(in: ppsStart ..< ppsEnd)

        spsData.withUnsafeBytes { spsRaw in
            ppsData.withUnsafeBytes { ppsRaw in
                let spsPtr = spsRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let ppsPtr = ppsRaw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                var paramSets = [spsPtr, ppsPtr]
                var sizes = [spsData.count, ppsData.count]
                var desc: CMVideoFormatDescription?
                let err = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &paramSets,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &desc
                )
                if err == noErr, let d = desc {
                    self.formatDesc = d
                    print("Updated FormatDesc successfully")
                    fflush(stdout)
                } else {
                    print("FormatDesc error: \(err)")
                    fflush(stdout)
                }
            }
        }
    }

    private func handleVideo(_ payload: Data) {
        guard let fmt = formatDesc else { return }
        guard payload.count > 8 else { return }

        let start = payload.startIndex
        let b0 = UInt32(payload[start])
        let b1 = UInt32(payload[start + 1])
        let b2 = UInt32(payload[start + 2])
        let b3 = UInt32(payload[start + 3])
        let low = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)

        let b4 = UInt32(payload[start + 4])
        let b5 = UInt32(payload[start + 5])
        let b6 = UInt32(payload[start + 6])
        let b7 = UInt32(payload[start + 7])
        let high = b4 | (b5 << 8) | (b6 << 16) | (b7 << 24)

        let sentTimeMs = Int64(UInt64(low) | (UInt64(high) << 32))

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let rawDelta = nowMs - sentTimeMs

        // Dynamic baseline latency calibration
        let nowSec = Date().timeIntervalSinceReferenceDate
        if minLatencyMs == Int64.max || rawDelta < minLatencyMs || (nowSec - lastLatencyResetTime > 10.0) {
            minLatencyMs = rawDelta
            lastLatencyResetTime = nowSec
        }

        let queueLag = rawDelta - minLatencyMs
        // If queue backlog exceeds 120ms (e.g. Wi-Fi momentary stutter), flush displayLayer to instantly catch up
        if queueLag > 120 {
            DispatchQueue.main.async { [weak self] in
                self?.layer.flush()
            }
            minLatencyMs = rawDelta
        }

        let count = payload.count - 8
        let mem = malloc(count)!
        payload.copyBytes(to: mem.assumingMemoryBound(to: UInt8.self), from: (start + 8) ..< (start + 8 + count))

        var blockBuf: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: mem,
            blockLength: count,
            blockAllocator: kCFAllocatorMalloc,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: count,
            flags: 0,
            blockBufferOut: &blockBuf
        )
        guard status == kCMBlockBufferNoErr, let bb = blockBuf else {
            free(mem)
            return
        }

        let pts = CMTimeMake(value: frameCount, timescale: 30)
        frameCount += 1

        var timingInfo = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: 30),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sb: CMSampleBuffer?
        var sampleSize = count
        let sbStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: fmt,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sb
        )

        guard sbStatus == noErr, let sampleBuffer = sb else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = CFArrayGetValueAtIndex(attachments, 0)
            let rawDict = unsafeBitCast(dict, to: CFMutableDictionary.self)
            CFDictionarySetValue(rawDict,
                                 unsafeBitCast(kCMSampleAttachmentKey_DisplayImmediately, to: UnsafeRawPointer.self),
                                 unsafeBitCast(kCFBooleanTrue, to: UnsafeRawPointer.self))
        }

        if self.layer.status == .failed {
            print("Layer failed: \(String(describing: self.layer.error))")
            fflush(stdout)
            DispatchQueue.main.async { [weak self] in
                self?.layer.flush()
            }
        }
        self.layer.enqueue(sampleBuffer)
    }
}
