import CZstd
import Foundation

/// Wraps libzstd with the window_log=17 setting required by the Divoom protocol.
enum Zstd {
    enum Error: Swift.Error { case ctxAlloc, compressFailed(String) }

    static func compress(_ input: Data, windowLog: Int32 = 17, level: Int32 = 3) throws -> Data {
        guard let cctx = ZSTD_createCCtx() else { throw Error.ctxAlloc }
        defer { ZSTD_freeCCtx(cctx) }

        var code = ZSTD_CCtx_setParameter(cctx, ZSTD_c_compressionLevel, level)
        if ZSTD_isError(code) != 0 { throw Error.compressFailed(Self.errString(code)) }
        code = ZSTD_CCtx_setParameter(cctx, ZSTD_c_windowLog, windowLog)
        if ZSTD_isError(code) != 0 { throw Error.compressFailed(Self.errString(code)) }
        // Disable the long-range mode and content-size flag so output matches the Android client.
        _ = ZSTD_CCtx_setParameter(cctx, ZSTD_c_contentSizeFlag, 0)

        let bound = ZSTD_compressBound(input.count)
        var out = Data(count: bound)
        let written = out.withUnsafeMutableBytes { outBuf -> Int in
            input.withUnsafeBytes { inBuf -> Int in
                ZSTD_compress2(
                    cctx,
                    outBuf.baseAddress, bound,
                    inBuf.baseAddress, input.count
                )
            }
        }
        if ZSTD_isError(written) != 0 { throw Error.compressFailed(Self.errString(written)) }
        out.count = written
        return out
    }

    private static func errString(_ code: Int) -> String {
        String(cString: ZSTD_getErrorName(code))
    }
}
