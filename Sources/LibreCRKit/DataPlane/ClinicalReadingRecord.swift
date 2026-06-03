import Foundation

/// Decoded clinical-stream record (0x08981ab8). Distinct from
/// `HistoricalReadingPage`: clinical pages are NOT six samples at
/// 5-minute stride — each page is a single time-point record with seven
/// 16-bit fields, emitted once per minute while the sensor is connected.
///
/// Field semantics were pinned against ground truth: at a known
/// `lifeCount` the realtime stream forwards both a current value and an
/// embedded historical value, and the clinical record emitted at the
/// same `lifeCount` reproduces both. At lifeCount 1578 the realtime
/// frame reported current = 160 mg/dL and embedded historical = 136
/// mg/dL (at the last 5-minute boundary, lifeCount 1560); the clinical
/// record at lifeCount 1578 carried word[5] = 160 and word[6] = 136.
/// That cross-check fixes the mapping:
///
/// | word | bytes | meaning                                              |
/// | ---- | ----- | ---------------------------------------------------- |
/// |  0   | 0–1   | `lifeCount` — current minute (page emitted per minute)|
/// |  1   | 2–3   | raw sensor channel (rises with glucose)              |
/// |  2   | 4–5   | raw sensor channel                                   |
/// |  3   | 6–7   | raw sensor channel (high byte pinned 0x0e; temp?)    |
/// |  4   | 8–9   | reserved / zero (only 0x0000 observed)               |
/// |  5   | 10–11 | current-minute glucose — equals realtime current     |
/// |  6   | 12–13 | most recent 5-min committed glucose — equals realtime|
/// |      |       | embedded historical                                  |
///
/// `currentGlucoseRaw` (word[5]) is the same per-minute value the
/// realtime stream emits, keyed at this record's own `lifeCount` (no
/// offset). `historicGlucoseRaw` (word[6]) is the same 5-minute committed
/// value the realtime stream carries as its embedded historical; its
/// lifeCount is the most recent 5-minute boundary, which this record does
/// not itself carry (the realtime frame's `historicalLifeCount` does).
///
/// Practical use: the clinical stream is the only published way to
/// backfill *minute-resolution* glucose during a disconnect window —
/// historical only persists 5-min boundaries. Apps integrating this
/// should consume `currentGlucose` keyed by `lifeCount` (offset 0).
/// `historicGlucoseRaw` is redundant with the realtime embedded
/// historical and should not be keyed at this record's `lifeCount`.
public struct ClinicalReadingRecord: Equatable, Sendable {
    public static let plaintextSize = 14

    /// LifeCount of this clinical record (per-minute granularity).
    public let lifeCount: UInt16

    /// Raw sensor channels (words 1–3). Not glucose; exposed for
    /// diagnostics. Word 3's high byte is pinned at 0x0e and is the
    /// suspected temperature channel.
    public let rawSensorWord1: UInt16
    public let rawSensorWord2: UInt16
    public let rawSensorWord3: UInt16

    /// Word 4 — only 0x0000 observed.
    public let reservedWord: UInt16

    /// Raw 16-bit current-minute glucose value, keyed at `lifeCount`.
    /// Equals the realtime stream's current value at the same lifeCount.
    /// Feed to `Libre3GlucoseValueStatus(rawSensorValue:)` for mg/dL.
    public let currentGlucoseRaw: UInt16

    /// Raw 16-bit most-recent 5-minute committed glucose value. Equals
    /// the realtime stream's embedded historical value; its lifeCount is
    /// the most recent 5-minute boundary, NOT this record's `lifeCount`.
    public let historicGlucoseRaw: UInt16

    public init(plaintext: Data) throws {
        guard plaintext.count == Self.plaintextSize else {
            throw ClinicalReadingRecordError.wrongPlaintextSize(plaintext.count)
        }
        let words = stride(from: 0, to: plaintext.count, by: 2).map { offset -> UInt16 in
            UInt16(plaintext[offset]) | (UInt16(plaintext[offset + 1]) << 8)
        }
        self.lifeCount = words[0]
        self.rawSensorWord1 = words[1]
        self.rawSensorWord2 = words[2]
        self.rawSensorWord3 = words[3]
        self.reservedWord = words[4]
        self.currentGlucoseRaw = words[5]
        self.historicGlucoseRaw = words[6]
    }

    public var currentGlucose: Libre3GlucoseValueStatus {
        Libre3GlucoseValueStatus(rawSensorValue: currentGlucoseRaw)
    }

    public var currentGlucoseMgDL: UInt16? {
        currentGlucose.displayMgDL
    }

    public var historicGlucose: Libre3GlucoseValueStatus {
        Libre3GlucoseValueStatus(rawSensorValue: historicGlucoseRaw)
    }

    public var historicGlucoseMgDL: UInt16? {
        historicGlucose.displayMgDL
    }
}

public enum ClinicalReadingRecordError: Error, Equatable {
    case wrongPlaintextSize(Int)
}
