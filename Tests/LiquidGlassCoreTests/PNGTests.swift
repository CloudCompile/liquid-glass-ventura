import XCTest
@testable import LiquidGlassCore

final class PNGTests: XCTestCase {

    private func u32(_ data: Data, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            value = (value << 8) | UInt32(data[data.startIndex + offset + i])
        }
        return value
    }

    func testEncodedPNGHasValidSignature() {
        let image = RGBAImage(width: 2, height: 2, fill: RGBAColor(r: 1, g: 0, b: 0, a: 1))
        let data = PNGEncoder.encode(image)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(data.prefix(8)), signature)
    }

    func testIHDRRecordsDimensionsAndFormat() {
        let image = RGBAImage(width: 37, height: 19, fill: .clear)
        let data = PNGEncoder.encode(image)
        // Signature (8) + length (4) + "IHDR" (4) = 16, then the fields.
        XCTAssertEqual(u32(data, 16), 37)
        XCTAssertEqual(u32(data, 20), 19)
        XCTAssertEqual(data[data.startIndex + 24], 8, "bit depth")
        XCTAssertEqual(data[data.startIndex + 25], 6, "colour type RGBA")
    }

    func testEncodedPNGEndsWithIEND() {
        let image = RGBAImage(width: 3, height: 3, fill: RGBAColor(r: 0, g: 1, b: 0, a: 1))
        let data = PNGEncoder.encode(image)
        // The final chunk is length (4) + "IEND" (4) + CRC (4).
        let tail = Array(data.suffix(12))
        XCTAssertEqual(u32(data, data.count - 12), 0, "IEND has an empty payload")
        XCTAssertEqual(Array(tail[4..<8]), Array("IEND".utf8))
    }

    func testEncodingIsDeterministic() {
        var image = RGBAImage(width: 5, height: 5)
        var rng = SplitMix64(seed: 42)
        for y in 0..<5 {
            for x in 0..<5 {
                let v = rng.unit()
                image.setColor(x: x, y: y, RGBAColor(r: v, g: 1 - v, b: 0.5, a: 1))
            }
        }
        XCTAssertEqual(PNGEncoder.encode(image), PNGEncoder.encode(image))
    }

    func testEmptyImageStillEncodes() {
        let data = PNGEncoder.encode(RGBAImage(width: 0, height: 0))
        XCTAssertGreaterThan(data.count, 8)
        XCTAssertEqual(u32(data, 16), 0)
        XCTAssertEqual(u32(data, 20), 0)
    }

    func testWriteCreatesTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("liquidglass-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = RGBAImage(width: 4, height: 4, fill: RGBAColor(r: 0, g: 0, b: 1, a: 1))
        try PNGEncoder.write(image, to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
