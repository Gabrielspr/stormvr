import Foundation

// Wire layouts are defined in Source/pc_driver/common/protocol.h.
enum Wire {
    struct Hand {
        let position: SIMD3<Float>
        let aim: SIMD3<Float>
        let ratio: Float
        let pinched: Bool
    }

    static func hands(
        device: UInt32, session: UInt32, sequence: UInt32, timeUs: UInt64,
        left: Hand?, right: Hand?
    ) -> Data {
        var packet = Packet(capacity: 92)
        packet.append(UInt32(0x3148424B)) // KBH1
        packet.append(device)
        packet.append(session)
        packet.append(sequence)
        packet.append(timeUs)
        packet.append(UInt16(3)) // Position and pinch enabled.
        packet.append(UInt16(0))
        for hand in [left, right] {
            packet.append(UInt32(hand.map { $0.pinched ? 3 : 1 } ?? 0))
            packet.append(hand?.position ?? .zero)
            packet.append(hand?.aim ?? .zero)
            packet.append(hand?.ratio ?? 1)
        }
        return packet.data
    }

    static func head(
        device: UInt32, session: UInt32, sequence: UInt32, timeUs: UInt64,
        rotation: SIMD4<Float>, recenter: UInt32, position: SIMD3<Float>?
    ) -> Data {
        var packet = Packet(capacity: 60)
        packet.append(UInt32(0x31485453)) // STH1
        packet.append(device)
        packet.append(session)
        packet.append(sequence)
        packet.append(timeUs)
        packet.append(UInt16(position == nil ? 0 : 1))
        packet.append(UInt8(position == nil ? 0 : 1))
        packet.append(UInt8(0))
        // SIMD uses xyzw. SteamVR expects wxyz.
        packet.append(rotation.w)
        packet.append(rotation.x)
        packet.append(rotation.y)
        packet.append(rotation.z)
        packet.append(recenter)
        packet.append(position ?? .zero)
        return packet.data
    }

    static func controller(
        sequence: UInt16, buttons: UInt16, stick: SIMD2<Float>, angles: SIMD3<Float>,
        uptimeMs: UInt32, left: Bool
    ) -> Data {
        var packet = Packet(capacity: 42)
        packet.append(UInt32(0x3154424B)) // KBT1
        packet.append(sequence)
        packet.append(buttons)
        packet.append(adc(stick.x))
        packet.append(adc(-stick.y))
        packet.append(angles)
        packet.append(SIMD3<Float>.zero) // Gyroscope fields are unused by the phone sender.
        packet.append(uptimeMs)
        packet.append(UInt8(0))
        packet.append(UInt8(left ? 0x0C : 0x04)) // Calibrated and, optionally, left-handed.
        return packet.data
    }

    private static func adc(_ axis: Float) -> UInt16 {
        UInt16(2048 + Int(max(-1, min(1, axis)) * 2047))
    }
}

private struct Packet {
    private(set) var data = Data()

    init(capacity: Int) { data.reserveCapacity(capacity) }

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: Float) { append(value.bitPattern) }

    mutating func append(_ value: SIMD3<Float>) {
        append(value.x)
        append(value.y)
        append(value.z)
    }
}
