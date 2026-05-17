import Foundation

/// Builds Divoom Minitoo SPP packets per the protocol reverse-engineered in
/// alvinunreal/divoom-minitoo-osx/PROTOCOL.md.
///
/// Envelope:  0x01 <declared_len LE16> <cmd> <body...> <checksum LE16> 0x02
///   declared_len = total_frame_len - 4
///   checksum     = sum(frame[1 ..< len-3]) & 0xFFFF, little-endian
///
/// Image command 0x8b is split into a START packet and a sequence of CHUNK packets
/// whose data fields concatenate into the image payload:
///
///   payload = 0x25 <frame_count u8> <speed_ms BE16> <rows u8> <cols u8> <zstd_len BE32> <zstd>
///
/// For a 128x128 still: frame_count=1, rows=8, cols=8 (16 px per block).
enum MinitooProtocol {
    static let imageCommand: UInt8 = 0x8b
    static let startMarker: UInt8 = 0x00
    static let chunkMarker: UInt8 = 0x01
    static let chunkSize = 256

    /// Build the full sequence of frames (start packet + chunks) to push one
    /// RGB888 128x128 image to the device. `pixels` must be exactly 128*128*3 bytes.
    static func encodeImage(rgb888 pixels: Data, speedMs: UInt16 = 1000) throws -> [Data] {
        precondition(pixels.count == 128 * 128 * 3, "expected 128x128 RGB888 buffer")

        let compressed = try Zstd.compress(pixels)
        var payload = Data()
        payload.append(0x25)                          // image payload tag
        payload.append(0x01)                          // frame_count
        payload.append(UInt8((speedMs >> 8) & 0xFF))  // speed BE16
        payload.append(UInt8(speedMs & 0xFF))
        payload.append(0x08)                          // row_blocks
        payload.append(0x08)                          // col_blocks
        let zlen = UInt32(compressed.count)
        payload.append(UInt8((zlen >> 24) & 0xFF))    // zstd_len BE32
        payload.append(UInt8((zlen >> 16) & 0xFF))
        payload.append(UInt8((zlen >> 8) & 0xFF))
        payload.append(UInt8(zlen & 0xFF))
        payload.append(compressed)

        var packets: [Data] = []
        packets.append(buildStartPacket(payloadSize: UInt32(payload.count)))

        var seq: UInt16 = 0
        var idx = 0
        while idx < payload.count {
            let end = min(idx + chunkSize, payload.count)
            let slice = payload.subdata(in: idx ..< end)
            packets.append(buildChunkPacket(payloadSize: UInt32(payload.count), seq: seq, data: slice))
            seq &+= 1
            idx = end
        }
        return packets
    }

    // MARK: - packet builders

    private static func buildStartPacket(payloadSize: UInt32) -> Data {
        // body = <0x00 marker> <payload_size LE32>
        var body = Data()
        body.append(startMarker)
        body.append(UInt8(payloadSize & 0xFF))
        body.append(UInt8((payloadSize >> 8) & 0xFF))
        body.append(UInt8((payloadSize >> 16) & 0xFF))
        body.append(UInt8((payloadSize >> 24) & 0xFF))
        return wrap(cmd: imageCommand, body: body)
    }

    private static func buildChunkPacket(payloadSize: UInt32, seq: UInt16, data: Data) -> Data {
        // body = <0x01 marker> <payload_size LE32> <seq LE16> <data>
        var body = Data()
        body.append(chunkMarker)
        body.append(UInt8(payloadSize & 0xFF))
        body.append(UInt8((payloadSize >> 8) & 0xFF))
        body.append(UInt8((payloadSize >> 16) & 0xFF))
        body.append(UInt8((payloadSize >> 24) & 0xFF))
        body.append(UInt8(seq & 0xFF))
        body.append(UInt8((seq >> 8) & 0xFF))
        body.append(data)
        return wrap(cmd: imageCommand, body: body)
    }

    /// Wrap a (cmd, body) pair in the standard envelope with declared_len + checksum + framing.
    private static func wrap(cmd: UInt8, body: Data) -> Data {
        // total_frame_len = 1 (start) + 2 (len) + 1 (cmd) + body + 2 (chk) + 1 (end)
        let total = 1 + 2 + 1 + body.count + 2 + 1
        let declared = UInt16(total - 4)

        var frame = Data(capacity: total)
        frame.append(0x01)
        frame.append(UInt8(declared & 0xFF))
        frame.append(UInt8((declared >> 8) & 0xFF))
        frame.append(cmd)
        frame.append(body)

        // checksum: sum of bytes [1 ..< total-3], i.e. declared_len + cmd + body
        var sum: UInt32 = 0
        for b in frame[1...] { sum &+= UInt32(b) }
        let chk = UInt16(sum & 0xFFFF)
        frame.append(UInt8(chk & 0xFF))
        frame.append(UInt8((chk >> 8) & 0xFF))
        frame.append(0x02)
        return frame
    }
}
