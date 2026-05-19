import Foundation
import IOBluetooth

/// Maintains a Bluetooth Classic RFCOMM channel to a paired Divoom Minitoo and
/// writes protocol packets to it. Auto-discovers the device on first send by
/// matching the paired-devices list against a name pattern ("divoom" / "minitoo").
final class MinitooConnection: NSObject {
    enum Error: Swift.Error {
        case noPairedDevice
        case openFailed(IOReturn)
        case writeFailed(IOReturn)
    }

    private let rfcommChannelID: BluetoothRFCOMMChannelID = 1  // JL_SPP
    private let namePattern = #"(?i)divoom|minitoo"#

    // Back-to-back writes overflow the Minitoo's receive buffer and it
    // silently drops the entire frame. 12ms between chunks matches the
    // upstream Python reference and is reliable in practice.
    private let interChunkDelay: TimeInterval = 0.012
    // Brief pause between the start packet and the first chunk so the device
    // can set up its image-receive state. PROTOCOL.md documents a chunk-
    // request ACK (0x8b 0x55 0x00) that the device is supposed to send
    // here, but the firmware on this Minitoo never sends it — it just
    // accepts chunks after a short settle. 200ms is conservative.
    private let postStartDelay: TimeInterval = 0.2

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private let q = DispatchQueue(label: "minitoo.write")

    var isConnected: Bool { channel != nil }
    var deviceDescription: String {
        guard let d = device else { return "<not connected>" }
        return "\(d.name ?? "<unknown>") (\(d.addressString ?? "?"))"
    }

    /// Send one encoded image frame (start packet + chunks). Reconnects on failure.
    func sendImage(_ image: MinitooProtocol.EncodedImage) throws {
        try q.sync {
            if !isConnected { try connect() }
            guard let ch = channel else { throw Error.noPairedDevice }

            try writeOne(ch, image.start)
            Thread.sleep(forTimeInterval: postStartDelay)
            for chunk in image.chunks {
                try writeOne(ch, chunk)
                Thread.sleep(forTimeInterval: interChunkDelay)
            }
        }
    }

    private func writeOne(_ ch: IOBluetoothRFCOMMChannel, _ packet: Data) throws {
        let rc = packet.withUnsafeBytes { raw -> IOReturn in
            let mut = UnsafeMutableRawPointer(mutating: raw.baseAddress!)
            return ch.writeSync(mut, length: UInt16(packet.count))
        }
        if rc != kIOReturnSuccess {
            closeQuietly()
            throw Error.writeFailed(rc)
        }
    }

    // MARK: - connection lifecycle

    /// IOBluetoothRFCOMMChannel delivers delegate callbacks on the run loop of
    /// the *opening* thread. We're called from a DispatchQueue worker that
    /// has no CFRunLoop, so rfcommChannelClosed (and any future rx use) would
    /// never fire. Bounce the open to the main thread so it lands on the
    /// AppKit run loop.
    private func connect() throws {
        if Thread.isMainThread {
            try connectOnMain()
        } else {
            var thrown: Swift.Error?
            DispatchQueue.main.sync {
                do { try self.connectOnMain() } catch { thrown = error }
            }
            if let e = thrown { throw e }
        }
    }

    private func connectOnMain() throws {
        guard let dev = findPairedDevice() else { throw Error.noPairedDevice }
        self.device = dev

        // Do NOT closeConnection() first to "clean up" the existing ACL.
        // Tearing down the link flashes a "no Bluetooth" icon on the device
        // and forces it back to clock-face mode, which silently drops 0x8b
        // image frames. Just join whatever connection is already up.
        if !dev.isConnected() {
            let openRc = dev.openConnection()
            if openRc != kIOReturnSuccess { throw Error.openFailed(openRc) }
        }

        var ch: IOBluetoothRFCOMMChannel?
        let rc = dev.openRFCOMMChannelSync(
            &ch,
            withChannelID: rfcommChannelID,
            delegate: self
        )
        if rc != kIOReturnSuccess { throw Error.openFailed(rc) }
        self.channel = ch
    }

    private func closeQuietly() {
        channel?.close()
        channel = nil
    }

    private func findPairedDevice() -> IOBluetoothDevice? {
        let paired = IOBluetoothDevice.pairedDevices() ?? []
        let regex = try? NSRegularExpression(pattern: namePattern)
        for any in paired {
            guard let dev = any as? IOBluetoothDevice, let name = dev.name else { continue }
            if let r = regex,
               r.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil {
                return dev
            }
        }
        return nil
    }
}

extension MinitooConnection: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        q.async { [weak self] in self?.channel = nil }
    }
}
