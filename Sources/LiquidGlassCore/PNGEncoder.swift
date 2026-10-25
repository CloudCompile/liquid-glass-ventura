import Foundation

/// A dependency-free PNG encoder.
///
/// Exists so the render tool and the tests can write real PNG files on any
/// platform without pulling in an image library. Scanlines are run through the
/// standard adaptive row filters, then compressed with a fixed-Huffman DEFLATE
/// stream, so output is a normal PNG that any decoder reads and the checked-in
/// screenshots stay a sensible size.
public enum PNGEncoder {

    public static func encode(_ image: RGBAImage) -> Data {
        var out = Data()
        out.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr = Data()
        ihdr.append(bigEndian: UInt32(image.width))
        ihdr.append(bigEndian: UInt32(image.height))
        ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit, RGBA, deflate, adaptive, no interlace
        out.append(chunk(type: "IHDR", payload: ihdr))

        out.append(chunk(type: "IDAT", payload: zlibCompress(filtered(image))))
        out.append(chunk(type: "IEND", payload: Data()))
        return out
    }

    public static func write(_ image: RGBAImage, to url: URL) throws {
        try encode(image).write(to: url)
    }

    private static func chunk(type: String, payload: Data) -> Data {
        var out = Data()
        out.append(bigEndian: UInt32(payload.count))
        let typeBytes = Array(type.utf8)
        out.append(contentsOf: typeBytes)
        out.append(payload)
        var crcInput = Data(typeBytes)
        crcInput.append(payload)
        out.append(bigEndian: crc32(crcInput))
        return out
    }

    /// Apply the PNG adaptive row filters, returning the filtered scanlines
    /// each prefixed with the chosen filter byte.
    private static func filtered(_ image: RGBAImage) -> Data {
        let bpp = 4
        let stride = image.width * bpp
        var out = Data(capacity: image.height * (stride + 1))
        var previous = [UInt8](repeating: 0, count: stride)
        var current = [UInt8](repeating: 0, count: stride)
        var candidate = [UInt8](repeating: 0, count: stride)

        for y in 0..<image.height {
            let rowStart = y * stride
            for i in 0..<stride { current[i] = image.pixels[rowStart + i] }

            // Score each of the five filters by the sum of absolute
            // differences, and keep the cheapest.
            var bestFilter = 0
            var bestScore = Int.max
            var best = [UInt8](repeating: 0, count: stride)
            for filter in 0...4 {
                var score = 0
                for i in 0..<stride {
                    let raw = Int(current[i])
                    let left = i >= bpp ? Int(current[i - bpp]) : 0
                    let up = Int(previous[i])
                    let upLeft = i >= bpp ? Int(previous[i - bpp]) : 0
                    let predicted: Int
                    switch filter {
                    case 1: predicted = left
                    case 2: predicted = up
                    case 3: predicted = (left + up) / 2
                    case 4: predicted = paeth(left, up, upLeft)
                    default: predicted = 0
                    }
                    let value = (raw - predicted) & 0xFF
                    candidate[i] = UInt8(value)
                    score += value < 128 ? value : 256 - value
                }
                if score < bestScore {
                    bestScore = score
                    bestFilter = filter
                    swap(&best, &candidate)
                }
            }

            out.append(UInt8(bestFilter))
            out.append(contentsOf: best)
            swap(&previous, &current)
        }
        return out
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a)
        let pb = abs(p - b)
        let pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    /// Wrap bytes in a zlib stream using fixed-Huffman DEFLATE with LZ77.
    private static func zlibCompress(_ input: Data) -> Data {
        var out = Data()
        out.append(contentsOf: [0x78, 0x9C]) // zlib header, default compression
        out.append(contentsOf: deflateFixed(input))
        out.append(bigEndian: adler32(input))
        return out
    }

    /// Fixed-Huffman DEFLATE with a hash-chain LZ77 match finder.
    ///
    /// Deliberately simple: one big block, greedy matching, a 32 KiB window.
    /// That is enough to shrink a screenshot by an order of magnitude without
    /// pulling in zlib.
    private static func deflateFixed(_ input: Data) -> Data {
        let bytes = [UInt8](input)
        var writer = BitWriter()
        writer.writeBits(1, count: 1) // final block
        writer.writeBits(1, count: 2) // fixed Huffman

        let windowSize = 32768
        let minMatch = 3
        let maxMatch = 258
        let hashSize = 1 << 15
        var head = [Int](repeating: -1, count: hashSize)
        var prev = [Int](repeating: -1, count: max(bytes.count, 1))

        @inline(__always) func hash(_ i: Int) -> Int {
            let h = (Int(bytes[i]) << 10) ^ (Int(bytes[i + 1]) << 5) ^ Int(bytes[i + 2])
            return h & (hashSize - 1)
        }

        var i = 0
        while i < bytes.count {
            var bestLen = 0
            var bestDist = 0
            if i + minMatch <= bytes.count {
                let h = hash(i)
                var candidate = head[h]
                var chain = 0
                let limit = max(0, i - windowSize)
                while candidate >= limit && chain < 64 {
                    let maxLen = min(maxMatch, bytes.count - i)
                    var length = 0
                    while length < maxLen && bytes[candidate + length] == bytes[i + length] {
                        length += 1
                    }
                    if length > bestLen {
                        bestLen = length
                        bestDist = i - candidate
                        if length >= maxLen { break }
                    }
                    candidate = prev[candidate]
                    chain += 1
                }
                prev[i] = head[h]
                head[h] = i
            }

            if bestLen >= minMatch {
                writeLength(bestLen, to: &writer)
                writeDistance(bestDist, to: &writer)
                // Register the skipped positions so later matches can find them.
                var j = i + 1
                let end = min(i + bestLen, bytes.count - minMatch)
                while j < end {
                    let h = hash(j)
                    prev[j] = head[h]
                    head[h] = j
                    j += 1
                }
                i += bestLen
            } else {
                writeLiteral(bytes[i], to: &writer)
                i += 1
            }
        }

        writeEndOfBlock(to: &writer)
        writer.flush()
        return writer.data
    }

    private static func writeLiteral(_ byte: UInt8, to writer: inout BitWriter) {
        let symbol = Int(byte)
        if symbol <= 143 {
            writer.writeCode(0b00110000 + symbol, count: 8)
        } else {
            writer.writeCode(0b110010000 + symbol - 144, count: 9)
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                     35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                      3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                       257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                                       8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static func writeLength(_ length: Int, to writer: inout BitWriter) {
        var index = 0
        while index < lengthBase.count - 1 && lengthBase[index + 1] <= length { index += 1 }
        let symbol = 257 + index
        if symbol <= 279 {
            writer.writeCode(0b0000000 + symbol - 256, count: 7)
        } else {
            writer.writeCode(0b11000000 + symbol - 280, count: 8)
        }
        let extra = lengthExtra[index]
        if extra > 0 {
            writer.writeBits(length - lengthBase[index], count: extra)
        }
    }

    private static func writeDistance(_ distance: Int, to writer: inout BitWriter) {
        var index = 0
        while index < distanceBase.count - 1 && distanceBase[index + 1] <= distance { index += 1 }
        // Distances use a fixed 5-bit code.
        writer.writeCode(index, count: 5)
        let extra = distanceExtra[index]
        if extra > 0 {
            writer.writeBits(distance - distanceBase[index], count: extra)
        }
    }

    private static func writeEndOfBlock(to writer: inout BitWriter) {
        // Symbol 256 in the fixed literal/length code is 7 zero bits.
        writer.writeCode(0, count: 7)
    }

    /// Bit writer for DEFLATE.
    ///
    /// DEFLATE packs bits into bytes starting from the least-significant bit,
    /// but Huffman codes are themselves stored most-significant bit first.
    /// `writeBits` handles the first rule (extra bits) and `writeCode` the
    /// second (Huffman codes).
    private struct BitWriter {
        var data = Data()
        private var buffer: UInt32 = 0
        private var bitCount = 0

        mutating func writeBits(_ value: Int, count: Int) {
            buffer |= UInt32(value & ((1 << count) - 1)) << bitCount
            bitCount += count
            while bitCount >= 8 {
                data.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                bitCount -= 8
            }
        }

        mutating func writeCode(_ value: Int, count: Int) {
            var reversed = 0
            for i in 0..<count {
                reversed |= ((value >> i) & 1) << (count - 1 - i)
            }
            writeBits(reversed, count: count)
        }

        mutating func flush() {
            if bitCount > 0 {
                data.append(UInt8(buffer & 0xFF))
                buffer = 0
                bitCount = 0
            }
        }
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }
}
