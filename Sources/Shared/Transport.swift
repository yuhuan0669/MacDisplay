import Foundation
import Network

// MARK: - Message Types
public let MSG_CONFIG: UInt8 = 0x01
public let MSG_VIDEO:  UInt8 = 0x02
public let MSG_FORMAT: UInt8 = 0x03
public let MSG_CURSOR: UInt8 = 0x04
public let MSG_PING:   UInt8 = 0xFF

// MARK: - Bonjour Service
public let kServiceType = "_macdisplay._tcp"
public let kServiceDomain = "local."

// MARK: - TCP Network Parameters
public func makeLowLatencyTCPParameters() -> NWParameters {
    let tcpOptions = NWProtocolTCP.Options()
    tcpOptions.noDelay = true                // Disable Nagle algorithm for immediate packet dispatch
    tcpOptions.enableKeepalive = true
    tcpOptions.keepaliveIdle = 2             // 2 seconds
    tcpOptions.keepaliveInterval = 1         // 1 second

    let params = NWParameters(tls: nil, tcp: tcpOptions)
    params.allowFastOpen = true
    params.serviceClass = .responsiveData    // Low-latency priority traffic
    return params
}

// MARK: - Config Payload
public struct DisplayConfig {
    public let width: UInt32
    public let height: UInt32
    public let fps: UInt32

    public init(width: UInt32, height: UInt32, fps: UInt32) {
        self.width = width; self.height = height; self.fps = fps
    }

    public var data: Data {
        var d = Data(count: 12)
        d.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: width.littleEndian,  toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: height.littleEndian, toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: fps.littleEndian,    toByteOffset: 8, as: UInt32.self)
        }
        return d
    }

    public init?(data: Data) {
        guard data.count >= 12 else { return nil }
        width  = data.withUnsafeBytes { UInt32(littleEndian: $0.load(fromByteOffset: 0, as: UInt32.self)) }
        height = data.withUnsafeBytes { UInt32(littleEndian: $0.load(fromByteOffset: 4, as: UInt32.self)) }
        fps    = data.withUnsafeBytes { UInt32(littleEndian: $0.load(fromByteOffset: 8, as: UInt32.self)) }
    }
}

// MARK: - Cursor Payload
/// Hardware cursor message: normalized coordinates [0.0 ... 1.0] relative to active display
public struct CursorMessage {
    public let visible: Bool
    public let x: Float           // Normalized coordinate: 0.0 ... 1.0
    public let y: Float           // Normalized coordinate: 0.0 ... 1.0
    public let cursorType: UInt8  // 0: arrow, 1: iBeam, 2: pointingHand

    public init(visible: Bool, x: Float, y: Float, cursorType: UInt8 = 0) {
        self.visible = visible
        self.x = x
        self.y = y
        self.cursorType = cursorType
    }

    public var data: Data {
        var d = Data(count: 10)
        d.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: visible ? UInt8(1) : UInt8(0), toByteOffset: 0, as: UInt8.self)
            ptr.storeBytes(of: x.bitPattern.littleEndian, toByteOffset: 1, as: UInt32.self)
            ptr.storeBytes(of: y.bitPattern.littleEndian, toByteOffset: 5, as: UInt32.self)
            ptr.storeBytes(of: cursorType, toByteOffset: 9, as: UInt8.self)
        }
        return d
    }

    public init?(data: Data) {
        guard data.count >= 10 else { return nil }
        visible = (data[0] != 0)
        let xBits = data.withUnsafeBytes { UInt32(littleEndian: $0.load(fromByteOffset: 1, as: UInt32.self)) }
        let yBits = data.withUnsafeBytes { UInt32(littleEndian: $0.load(fromByteOffset: 5, as: UInt32.self)) }
        x = Float(bitPattern: xBits)
        y = Float(bitPattern: yBits)
        cursorType = data[9]
    }
}

// MARK: - Framed Transport
/// Wire format per message: [4-byte payload-len LE][1-byte type][payload]
public final class FramedConnection {
    public let connection: NWConnection
    private var buf = Data()
    private let lock = NSLock()

    // Backpressure tracker: indicates whether a previous video packet is still in flight
    public var isBusySending = false

    public init(_ connection: NWConnection) {
        self.connection = connection
    }

    public func send(type: UInt8, payload: Data, completion: ((NWError?) -> Void)? = nil) {
        var msg = Data(capacity: 5 + payload.count)
        var len = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &len) { msg.append(contentsOf: $0) }
        msg.append(type)
        msg.append(payload)

        connection.send(content: msg, completion: .contentProcessed { error in
            completion?(error)
        })
    }

    public func startReceiving(handler: @escaping (UInt8, Data) -> Void) {
        receive(handler: handler)
    }

    private func receive(handler: @escaping (UInt8, Data) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) {
            [weak self] data, _, isDone, error in
            guard let self = self else { return }
            if let d = data, !d.isEmpty {
                self.lock.lock()
                self.buf.append(d)
                self.lock.unlock()
                self.drain(handler: handler)
            }
            if !isDone && error == nil {
                self.receive(handler: handler)
            } else if isDone || error != nil {
                self.connection.cancel()
            }
        }
    }

    private func drain(handler: @escaping (UInt8, Data) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        while buf.count >= 5 {
            let start = buf.startIndex
            let b0 = UInt32(buf[start])
            let b1 = UInt32(buf[start + 1])
            let b2 = UInt32(buf[start + 2])
            let b3 = UInt32(buf[start + 3])
            let payloadLen = Int(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))

            let total = 5 + payloadLen
            guard buf.count >= total else { break }
            let type = buf[start + 4]
            let payload = buf.subdata(in: (start + 5) ..< (start + total))
            buf.removeFirst(total)
            if buf.isEmpty {
                buf = Data()
            }
            lock.unlock()
            handler(type, payload)
            lock.lock()
        }
    }
}
