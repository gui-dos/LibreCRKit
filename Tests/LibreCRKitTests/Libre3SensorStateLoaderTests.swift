import XCTest
@testable import LibreCRKit

final class Libre3SensorStateLoaderTests: XCTestCase {
    func testLoadsHexBlePIN() throws {
        let json = Data("""
        {"serialNumber":"0RRC989AQ","bleAddress":"CC:22:DF:B8:F9:58","blePIN":"3225ec72","receiverID":"78830d6f","source":"test","lastGlucoseLifeCount":1073,"lastGlucoseMgDL":151}
        """.utf8)

        let state = try Libre3SensorStateLoader.load(fromJSON: json)
        XCTAssertEqual(state.serialNumber, "0RRC989AQ")
        XCTAssertEqual(state.bleAddress, "CC:22:DF:B8:F9:58")
        XCTAssertEqual(state.blePIN.hex, "3225ec72")
        XCTAssertEqual(state.receiverID?.value, 0x6f0d8378)
        XCTAssertEqual(state.receiverID?.littleEndianHex, "78830d6f")
        XCTAssertEqual(state.source, "test")
        XCTAssertEqual(state.lastGlucoseLifeCount, 1073)
        XCTAssertEqual(state.lastGlucoseMgDL, 151)
    }

    func testLoadsRealmBase64BlePIN() throws {
        let json = Data(#"{"blePIN":"MiXscg=="}"#.utf8)

        let state = try Libre3SensorStateLoader.load(fromJSON: json)
        XCTAssertEqual(state.blePIN.hex, "3225ec72")
    }

    func testRejectsWrongPINSize() {
        let json = Data(#"{"blePIN":"3225ec"}"#.utf8)

        XCTAssertThrowsError(try Libre3SensorStateLoader.load(fromJSON: json)) { error in
            XCTAssertEqual(error as? Libre3SensorStateError, .wrongBlePINSize(3))
        }
    }

    func testEncodesRoundTrippableHexJSON() throws {
        let state = try Libre3SensorState(
            serialNumber: "0RRC989AQ",
            blePIN: Data([0x32, 0x25, 0xec, 0x72]),
            bleAddress: "CC:22:DF:B8:F9:58",
            receiverID: Libre3ReceiverID(0x6f0d8378),
            source: "NFC activation response",
            lastGlucoseLifeCount: 1073,
            lastGlucoseMgDL: 151
        )

        let encoded = try Libre3SensorStateLoader.jsonData(from: state)
        let decoded = try Libre3SensorStateLoader.load(fromJSON: encoded)

        XCTAssertEqual(decoded, state)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains(#""blePIN" : "3225ec72""#))
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains(#""receiverID" : "78830d6f""#))
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains(#""lastGlucoseLifeCount" : 1073"#))
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains(#""lastGlucoseMgDL" : 151"#))
    }

    func testUpdatesLastGlucoseMetadata() throws {
        let state = try Libre3SensorState(
            serialNumber: "0RRC989AQ",
            blePIN: Data([0x32, 0x25, 0xec, 0x72]),
            bleAddress: "CC:22:DF:B8:F9:58"
        )

        let updated = try state.updatingLastGlucose(lifeCount: 1080, mgDL: 149)

        XCTAssertEqual(updated.serialNumber, state.serialNumber)
        XCTAssertEqual(updated.blePIN, state.blePIN)
        XCTAssertEqual(updated.lastGlucoseLifeCount, 1080)
        XCTAssertEqual(updated.lastGlucoseMgDL, 149)
    }
}
