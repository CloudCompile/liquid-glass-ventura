import XCTest
@testable import LiquidGlassCore

/// Decodes the encoder's own output, all the way through the DEFLATE stream.
///
/// `PNGEncoder` contains a hand-rolled fixed-Huffman compressor and a PNG row
/// filter pass. A byte-level header check would not catch a Huffman coding
/// mistake, so these tests inflate the zlib payload and reverse the filters,
/// then assert the pixels come back exactly.
final class PNGRoundTripTests: XCTestCase {

    // MARK: - Cases

    func testFlatImageRoundTrips() throws {
        let image = RGBAImage(width: 40, height: 24, fill: RGBAColor(r: 0.25, g: 0.5, b: 0.75, a: 1))
        XCTAssertEqual(try decode(PNGEncoder.encode(image)), image)
    }

    func testGradientImageRoundTrips() throws {
        var image = RGBAImage(width: 63, height: 37)
        for y in 0..<37 {
            for x in 0..<63 {
                image.setColor(x: x, y: y, RGBAColor(
                    r: Double(x) / 62, g: Double(y) / 36, b: 0.5, a: 1
                ))
            }
        }
        XCTAssertEqual(try decode(PNGEncoder.encode(image)), image)
    }

    func testNoisyImageRoundTrips() throws {
        // Noise defeats LZ77 matching, so this is the literal-heavy path.
        var image = RGBAImage(width: 64, height: 64)
        var rng = SplitMix64(seed: 0xABCDEF)
        for y in 0..<64 {
            for x in 0..<64 {
                image.setColor(x: x, y: y, RGBAColor(
                    r: rng.unit(), g: rng.unit(), b: rng.unit(), a: rng.unit()
                ))
            }
        }
        XCTAssertEqual(try decode(PNGEncoder.encode(image)), image)
    }

    func testRepeatingImageRoundTrips() throws {
        // A long run of identical bytes is the best case for LZ77, and
        // exercises the maximum-length (258) match path.
        let image = RGBAImage(width: 200, height: 8, fill: RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 1))
        XCTAssertEqual(try decode(PNGEncoder.encode(image)), image)
    }

    func testSinglePixelRoundTrips() throws {
        let image = RGBAImage(width: 1, height: 1, fill: RGBAColor(r: 1, g: 0, b: 0, a: 0.5))
        XCTAssertEqual(try decode(PNGEncoder.encode(image)), image)
    }

    func testEmptyImageRoundTrips() throws {
        XCTAssertEqual(try decode(PNGEncoder.encode(RGBAImage(width: 0, height: 0))), RGBAImage(width: 0, height: 0))
    }

    func testCompressionBeatsRawForRepeatingContent() {
        let image = RGBAImage(width: 256, height: 256, fill: RGBAColor(r: 0.4, g: 0.6, b: 0.8, a: 1))
        let raw = image.width * image.height * 4
        XCTAssertLessThan(PNGEncoder.encode(image).count, raw / 10)
    }

    // MARK: - Minimal PNG reader

    /// Parse a PNG produced by `PNGEncoder` back into an `RGBAImage`.
    private func decode(_ data: Data) throws -> RGBAImage {
        let bytes = [UInt8](data)
        guard bytes.count > 8, Array(bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else {
            throw Failure.badSignature
        }

        var offset = 8
        var width = 0
        var height = 0
        var idat = Data()
        while offset + 8 <= bytes.count {
            let length = Int(be32(bytes, offset))
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + length
            guard payloadEnd <= bytes.count else { throw Failure.truncated }
            let payload = Data(bytes[payloadStart..<payloadEnd])
            switch type {
            case "IHDR":
                width = Int(be32(bytes, payloadStart))
                height = Int(be32(bytes, payloadStart + 4))
            case "IDAT":
                idat.append(payload)
            default:
                break
            }
            offset = payloadEnd + 4 // skip the CRC
        }

        let raw = try inflateZlib(idat)
        let stride = width * 4
        guard raw.count == (stride + 1) * height else {
            throw Failure.badSize(expected: (stride + 1) * height, actual: raw.count)
        }

        var pixels = [UInt8](repeating: 0, count: stride * height)
        var previous = [UInt8](repeating: 0, count: stride)
        var current = [UInt8](repeating: 0, count: stride)
        for y in 0..<height {
            let base = y * (stride + 1)
            let filter = raw[base]
            for i in 0..<stride {
                let encoded = Int(raw[base + 1 + i])
                let left = i >= 4 ? Int(current[i - 4]) : 0
                let up = Int(previous[i])
                let upLeft = i >= 4 ? Int(previous[i - 4]) : 0
                let predicted: Int
                switch filter {
                case 1: predicted = left
                case 2: predicted = up
                case 3: predicted = (left + up) / 2
                case 4: predicted = paeth(left, up, upLeft)
                default: predicted = 0
                }
                current[i] = UInt8((encoded + predicted) & 0xFF)
            }
            for i in 0..<stride { pixels[y * stride + i] = current[i] }
            swap(&previous, &current)
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    private func be32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    // MARK: - Inflate

    /// A fixed-Huffman DEFLATE decoder, the inverse of the encoder.
    private func inflateZlib(_ stream: Data) throws -> [UInt8] {
        let bytes = [UInt8](stream)
        guard bytes.count >= 2, bytes[0] == 0x78 else { throw Failure.badZlibHeader }
        var bitReader = BitReader(bytes: bytes, offset: 2)
        var out: [UInt8] = []

        while true {
            let isFinal = try bitReader.read(1)
            let type = try bitReader.read(2)
            guard type == 1 else { throw Failure.unsupportedBlockType(type) }
            try inflateFixedBlock(&bitReader, into: &out)
            if isFinal == 1 { break }
        }
        return out
    }

    private func inflateFixedBlock(_ reader: inout BitReader, into out: inout [UInt8]) throws {
        while true {
            let symbol = try readFixedSymbol(&reader)
            if symbol < 256 {
                out.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthIndex < Self.lengthBase.count else { throw Failure.badSymbol(symbol) }
                let length = Self.lengthBase[lengthIndex] + (try reader.read(Self.lengthExtra[lengthIndex]))
                let distanceCode = try reader.readCode(5)
                guard distanceCode < Self.distanceBase.count else { throw Failure.badSymbol(distanceCode) }
                let distance = Self.distanceBase[distanceCode] + (try reader.read(Self.distanceExtra[distanceCode]))
                guard distance <= out.count else { throw Failure.badDistance(distance) }
                let start = out.count - distance
                for i in 0..<length { out.append(out[start + i]) }
            }
        }
    }

    /// Decode one symbol from the fixed literal/length code.
    ///
    /// The fixed code has canonical code lengths of 7, 8, and 9 bits, and the
    /// codes are written most-significant bit first, so a peeked LSB-first
    /// value has to be bit-reversed before it can be compared to a code.
    private func readFixedSymbol(_ reader: inout BitReader) throws -> Int {
        let seven = reverse(try reader.peek(7), 7)
        if seven <= 0x17 { // 0000000..0010111 -> symbols 256..279
            _ = try reader.read(7)
            return 256 + seven
        }
        let eight = reverse(try reader.peek(8), 8)
        if eight >= 0x30 && eight <= 0xBF { // 00110000..10111111 -> 0..143
            _ = try reader.read(8)
            return eight - 0x30
        }
        if eight >= 0xC0 && eight <= 0xC7 { // 11000000..11000111 -> 280..287
            _ = try reader.read(8)
            return 280 + (eight - 0xC0)
        }
        let nine = reverse(try reader.peek(9), 9)
        guard nine >= 0x190 && nine <= 0x1FF else { throw Failure.badSymbol(nine) }
        _ = try reader.read(9)
        return 144 + (nine - 0x190)
    }

    private func reverse(_ value: Int, _ count: Int) -> Int {
        var result = 0
        for i in 0..<count { result |= ((value >> i) & 1) << (count - 1 - i) }
        return result
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

    private enum Failure: Error, CustomStringConvertible {
        case badSignature, truncated, badZlibHeader, badSize(expected: Int, actual: Int)
        case unsupportedBlockType(Int), badSymbol(Int), badDistance(Int)

        var description: String {
            switch self {
            case .badSignature: return "not a PNG"
            case .truncated: return "truncated chunk"
            case .badZlibHeader: return "bad zlib header"
            case .badSize(let e, let a): return "expected \(e) bytes, got \(a)"
            case .unsupportedBlockType(let t): return "unsupported DEFLATE block type \(t)"
            case .badSymbol(let s): return "bad Huffman symbol \(s)"
            case .badDistance(let d): return "bad match distance \(d)"
            }
        }
    }

    private struct BitReader {
        let bytes: [UInt8]
        var offset: Int
        private var buffer: UInt32 = 0
        private var bitCount = 0

        init(bytes: [UInt8], offset: Int) {
            self.bytes = bytes
            self.offset = offset
        }

        mutating func read(_ count: Int) throws -> Int {
            try fill(count)
            let value = Int(buffer & ((1 << count) - 1))
            buffer >>= count
            bitCount -= count
            return value
        }

        mutating func peek(_ count: Int) throws -> Int {
            try fill(count)
            return Int(buffer & ((1 << count) - 1))
        }

        /// Read a Huffman-style code, which is stored most-significant bit first.
        mutating func readCode(_ count: Int) throws -> Int {
            var value = 0
            for _ in 0..<count { value = (value << 1) | (try read(1)) }
            return value
        }

        private mutating func fill(_ count: Int) throws {
            while bitCount < count {
                guard offset < bytes.count else { throw Failure.truncated }
                buffer |= UInt32(bytes[offset]) << bitCount
                offset += 1
                bitCount += 8
            }
        }
    }
}
