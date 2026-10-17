import Foundation

public enum ProtocolError: Error, Equatable {
  case invalidFrame
  case invalidEQ
  case invalidGain
}

public struct Frame: Equatable {
  public let header: UInt8
  public let command: UInt8
  public let payload: [UInt8]

  public static func request(_ command: UInt8, payload: [UInt8] = []) -> Data {
    precondition(payload.count <= UInt16.max)
    var bytes: [UInt8] =
      [
        0xAA, 0xEC, command,
        UInt8(payload.count >> 8), UInt8(payload.count & 0xFF),
      ] + payload
    bytes.append(checksum(bytes))
    return Data(bytes)
  }

  public static func decode(_ bytes: [UInt8]) throws -> Frame {
    guard bytes.count >= 6,
      bytes[0] == 0xBB || bytes[0] == 0xCC,
      bytes[1] == 0xEC,
      bytes.count == 6 + Int(bytes[3]) * 256 + Int(bytes[4]),
      bytes.last == checksum(Array(bytes.dropLast()))
    else { throw ProtocolError.invalidFrame }
    return Frame(header: bytes[0], command: bytes[2], payload: Array(bytes[5..<bytes.count - 1]))
  }

  private static func checksum(_ bytes: [UInt8]) -> UInt8 {
    UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 + Int($1) })
  }
}

/// Reassembles fragmented/coalesced BLE notifications and discards invalid frames.
public struct FrameDecoder {
  private var buffer: [UInt8] = []
  public init() {}

  public mutating func append(_ data: Data) -> [Frame] {
    buffer.append(contentsOf: data)
    var frames: [Frame] = []
    while buffer.count >= 6 {
      guard buffer[0] == 0xBB || buffer[0] == 0xCC, buffer[1] == 0xEC else {
        buffer.removeFirst()
        continue
      }
      let length = Int(buffer[3]) * 256 + Int(buffer[4])
      guard length <= 4096 else {
        buffer.removeFirst()
        continue
      }
      guard buffer.count >= length + 6 else { break }
      let bytes = Array(buffer.prefix(length + 6))
      if let frame = try? Frame.decode(bytes) {
        frames.append(frame)
        buffer.removeFirst(length + 6)
      } else {
        buffer.removeFirst()
      }
    }
    return frames
  }
}

public enum CustomEQ {
  public static let frequencies = [62, 250, 1000, 4000, 8000, 16000]

  public static func encodeGain(_ db: Double) throws -> UInt8 {
    guard db.isFinite, (-3...3).contains(db), db * 2 == (db * 2).rounded()
    else { throw ProtocolError.invalidGain }
    return UInt8((db + 3) * 2)
  }

  public static func writePayload(band: Int, code: UInt8) throws -> [UInt8] {
    guard frequencies.indices.contains(band), code <= 12 else {
      throw ProtocolError.invalidEQ
    }
    let frequency = frequencies[band]
    return [UInt8(band), UInt8(frequency >> 8), UInt8(frequency & 0xFF), code]
  }

  /// Format 02: six records of <index, frequency high, frequency low, gain>.
  /// A timestamp/name suffix is allowed and is never rewritten by this codec.
  public static func decode(_ payload: [UInt8]) throws -> [UInt8] {
    guard payload.count >= 26, payload[0] == 2, payload[1] == 6 else {
      throw ProtocolError.invalidEQ
    }
    var codes = [UInt8](repeating: 0, count: 6)
    var seen = Set<Int>()
    for i in 0..<6 {
      let offset = 2 + i * 4
      let band = Int(payload[offset])
      guard frequencies.indices.contains(band), seen.insert(band).inserted,
        Int(payload[offset + 1]) * 256 + Int(payload[offset + 2]) == frequencies[band],
        payload[offset + 3] <= 12
      else { throw ProtocolError.invalidEQ }
      codes[band] = payload[offset + 3]
    }
    return codes
  }
}
