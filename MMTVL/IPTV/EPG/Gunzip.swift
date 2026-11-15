import Foundation
import zlib

/// File-to-file gzip inflate. Apple's Compression framework is raw DEFLATE and can't read gzip.
nonisolated enum Gunzip {
    enum GunzipError: Error, Equatable {
        case zlib(Int32)
        /// M7j step 8 (security L3): the output passed `maxOutputBytes`.
        case tooLarge
    }

    private static let chunkSize = 256 * 1024

    /// First two bytes are 1F 8B.
    static func isGzip(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 2) ?? Data()
        return header == Data([0x1F, 0x8B])
    }

    /// Streams `source` → `destination` in 256 KB chunks with inflateInit2_(…, 15 + 32, …).
    /// On Z_STREAM_END with input left (concatenated members), inflateReset and continue. Throws on zlib errors, and
    /// `tooLarge` once more than `maxOutputBytes` (nil: no limit) would be written.
    static func decompress(_ source: URL, to destination: URL, maxOutputBytes: Int? = nil) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var stream = z_stream()
        var status = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw GunzipError.zlib(status) }
        defer { inflateEnd(&stream) }

        var outBuffer = [UInt8](repeating: 0, count: chunkSize)
        var finishedMember = false
        var written = 0
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            var inBytes = [UInt8](chunk)
            let inCount = inBytes.count
            try inBytes.withUnsafeMutableBufferPointer { inPointer in
                stream.next_in = inPointer.baseAddress
                stream.avail_in = uInt(inCount)
                while stream.avail_in > 0 {
                    if finishedMember {
                        // Another gzip member follows the one that just ended.
                        status = inflateReset(&stream)
                        guard status == Z_OK else { throw GunzipError.zlib(status) }
                        finishedMember = false
                    }
                    let produced: Int = try outBuffer.withUnsafeMutableBufferPointer { outPointer in
                        stream.next_out = outPointer.baseAddress
                        stream.avail_out = uInt(chunkSize)
                        status = inflate(&stream, Z_NO_FLUSH)
                        guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                            throw GunzipError.zlib(status)
                        }
                        return chunkSize - Int(stream.avail_out)
                    }
                    written += produced
                    if let maxOutputBytes, written > maxOutputBytes { throw GunzipError.tooLarge }
                    if produced > 0 { output.write(Data(outBuffer[0..<produced])) }
                    if status == Z_STREAM_END { finishedMember = true }
                    if status == Z_BUF_ERROR && produced == 0 { break }
                }
            }
        }
        guard finishedMember else { throw GunzipError.zlib(Z_DATA_ERROR) }
    }
}
