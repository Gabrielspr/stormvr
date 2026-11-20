import Foundation

@main
enum WireCheck {
    static func main() {
        let head = Wire.head(
            device: 0x11223344, session: 0x55667788, sequence: 0x99aabbcc,
            timeUs: 0x0102030405060708, rotation: SIMD4(0.25, -0.5, 0.75, 1),
            recenter: 2, position: SIMD3(1.25, -2.5, 0.125)
        )
        check(head, """
            53544831 44332211 88776655 ccbbaa99 0807060504030201 01000100
            0000803f 0000803e 000000bf 0000403f 02000000 0000a03f 000020c0 0000003e
            """)

        let rotationOnly = Wire.head(
            device: 1, session: 1, sequence: 1, timeUs: 1,
            rotation: SIMD4(0, 0, 0, 1), recenter: 0, position: nil
        )
        precondition(rotationOnly.count == 60)
        precondition(rotationOnly[24..<28].allSatisfy { $0 == 0 } && rotationOnly.suffix(12).allSatisfy { $0 == 0 })

        let controller = Wire.controller(
            sequence: 0x1234, buttons: 0x0182, stick: SIMD2(1, 1), angles: SIMD3(90, -45, 180),
            uptimeMs: 0x01020304, left: true
        )
        check(controller, """
            4b425431 3412 8201 ff0f 0100 0000b442 000034c2 00003443
            00000000 00000000 00000000 04030201 000c
            """)

        let hand = Wire.Hand(position: SIMD3(0.25, -0.5, -1), aim: SIMD3(0, 0, -1), ratio: 0.125, pinched: true)
        check(Wire.hands(device: 5, session: 6, sequence: 7, timeUs: 8, left: nil, right: hand), """
            4b424831 05000000 06000000 07000000 0800000000000000 03000000
            00000000 00000000 00000000 00000000 00000000 00000000 00000000 0000803f
            03000000 0000803e 000000bf 000080bf 00000000 00000000 000080bf 0000003e
            """)
        print("StormVR UDP wire format OK")
    }

    private static func check(_ data: Data, _ hex: String) {
        let actual = data.map { String(format: "%02x", $0) }.joined()
        let expected = hex.filter { !$0.isWhitespace }
        precondition(actual == expected, "UDP payload mismatch: \(actual) != \(expected)")
    }
}
