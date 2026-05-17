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

    private let rfcommChannelID: BluetoothRFCOMMChannelID = 1
    private let namePattern = #"(?i)divoom|minitoo"#

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private let q = DispatchQueue(label: "minitoo.write")

    var isConnected: Bool { channel != nil }
    var deviceDescription: String {
        guard let d = device else { return "<not connected>" }
        return "\(d.name ?? "<unknown>") (\(d.addressString ?? "?"))"
    }

    /// Synchronously sends the given packets in order. Reconnects on failure.
    func send(_ packets: [Data]) throws {
        try q.sync {
            if !isConnected { try connect() }
            guard let ch = channel else { throw Error.noPairedDevice }
            for packet in packets {
                let rc = packet.withUnsafeBytes { raw -> IOReturn in
                    let mut = UnsafeMutableRawPointer(mutating: raw.baseAddress!)
                    return ch.writeSync(mut, length: UInt16(packet.count))
                }
                if rc != kIOReturnSuccess {
                    closeQuietly()
                    throw Error.writeFailed(rc)
                }
            }
        }
    }

    // MARK: - connection lifecycle

    private func connect() throws {
        guard let dev = findPairedDevice() else { throw Error.noPairedDevice }
        self.device = dev

        if !dev.isConnected() {
            let rc = dev.openConnection()
            if rc != kIOReturnSuccess { throw Error.openFailed(rc) }
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

    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        // ignore
    }
}
