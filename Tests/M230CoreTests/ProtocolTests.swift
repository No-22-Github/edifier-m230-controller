import XCTest

@testable import M230Core

final class ProtocolTests: XCTestCase {
  private let neutral: [UInt8] = [
    2, 6, 0, 0, 62, 6, 1, 0, 250, 6, 2, 3, 232, 6,
    3, 15, 160, 6, 4, 31, 64, 6, 5, 62, 128, 6,
  ]

  func testRequestsMatchObservedM230Frames() throws {
    XCTAssertEqual(Array(Frame.request(0xD0)), [0xAA, 0xEC, 0xD0, 0, 0, 0x66])
    XCTAssertEqual(Array(Frame.request(0x43)), [0xAA, 0xEC, 0x43, 0, 0, 0xD9])
    XCTAssertEqual(
      Array(Frame.request(0x44, payload: try CustomEQ.writePayload(band: 0, code: 7))),
      [0xAA, 0xEC, 0x44, 0, 4, 0, 0, 0x3E, 7, 0x23])
  }

  func testReplyValidation() throws {
    let battery: [UInt8] = [0xBB, 0xEC, 0xD0, 0, 1, 0x3C, 0xB4]
    let decoded = try Frame.decode(battery)
    XCTAssertEqual(decoded.command, 0xD0)
    XCTAssertEqual(decoded.payload, [60])
    XCTAssertEqual(decoded.header, 0xBB)
    XCTAssertThrowsError(try Frame.decode(Array(battery.dropLast())))
    var corrupt = battery
    corrupt[5] = 100
    XCTAssertThrowsError(try Frame.decode(corrupt))
    XCTAssertThrowsError(try Frame.decode([0xAA, 0xEC, 0xD0, 0, 0, 0x66]))
    XCTAssertEqual(try Frame.decode([0xCC, 0xEC, 0xCA, 0, 1, 1, 0x84]).header, 0xCC)
  }

  func testFragmentedAndCoalescedNotifications() {
    let a: [UInt8] = [0xBB, 0xEC, 0xD0, 0, 1, 0x3C, 0xB4]
    let b: [UInt8] = [0xBB, 0xEC, 0xD5, 0, 1, 5, 0x82]
    var decoder = FrameDecoder()
    XCTAssertTrue(decoder.append(Data([0x00, 0xFF] + Array(a.prefix(4)))).isEmpty)
    let frames = decoder.append(Data(Array(a.dropFirst(4)) + b))
    XCTAssertEqual(frames.map(\.command), [0xD0, 0xD5])
    XCTAssertEqual(frames.map(\.payload), [[60], [5]])
  }

  func testDecoderRecoversAfterBadChecksumAndOversizedLength() {
    var decoder = FrameDecoder()
    let good: [UInt8] = [0xBB, 0xEC, 0xD0, 0, 1, 0x3C, 0xB4]
    let noise: [UInt8] = [0xBB, 0xEC, 1, 0xFF, 0xFF, 0, 0xBB, 0xEC, 0xD0, 0, 1, 60, 0]
    XCTAssertEqual(decoder.append(Data(noise + good)).map(\.payload), [[60]])
  }

  func testEveryGainStepAndFrequency() throws {
    for code in UInt8(0)...UInt8(12) {
      XCTAssertEqual(try CustomEQ.encodeGain(Double(code) * 0.5 - 3), code)
    }
    for (band, frequency) in CustomEQ.frequencies.enumerated() {
      let payload = try CustomEQ.writePayload(band: band, code: 6)
      XCTAssertEqual(payload[0], UInt8(band))
      XCTAssertEqual(Int(payload[1]) * 256 + Int(payload[2]), frequency)
    }
    for invalid in [Double.nan, .infinity, -.infinity, -3.5, 3.5, 0.1] {
      XCTAssertThrowsError(try CustomEQ.encodeGain(invalid))
    }
    XCTAssertThrowsError(try CustomEQ.writePayload(band: -1, code: 6))
    XCTAssertThrowsError(try CustomEQ.writePayload(band: 6, code: 6))
    XCTAssertThrowsError(try CustomEQ.writePayload(band: 0, code: 13))
  }

  func testNeutralMixedReorderedAndSuffixedEQ() throws {
    XCTAssertEqual(try CustomEQ.decode(neutral), [6, 6, 6, 6, 6, 6])
    var mixed = neutral
    mixed[5] = 0
    mixed[9] = 12
    mixed[13] = 5
    XCTAssertEqual(try CustomEQ.decode(mixed), [0, 12, 5, 6, 6, 6])
    var records: [UInt8] = []
    for band in (0..<6).reversed() {
      let offset = 2 + band * 4
      records.append(contentsOf: neutral[offset..<(offset + 4)])
    }
    XCTAssertEqual(try CustomEQ.decode([2, 6] + records + [0, 0, 0, 0, 65]), [6, 6, 6, 6, 6, 6])
  }

  func testRejectsOtherProfilesAndMalformedEQ() {
    XCTAssertThrowsError(try CustomEQ.decode(Array(neutral.dropLast())))
    for (offset, value): (Int, UInt8) in [(0, 3), (1, 9), (6, 0), (2, 6), (4, 63), (5, 13)] {
      var malformed = neutral
      malformed[offset] = value
      XCTAssertThrowsError(try CustomEQ.decode(malformed), "offset \(offset)")
    }
  }
}
