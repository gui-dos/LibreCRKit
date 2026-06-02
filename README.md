# LibreCRKit

LibreCRKit is the clean-room Swift package for Libre 3 pairing, BLE transport,
authorization, sensor recovery, and post-auth data-plane decoding. It is built
as a reusable foundation for any iOS app that wants to integrate a Libre
sensor. The standalone `Apps/LibreCR` app is the live-device harness around
this package.

This repo contains:

- `Package.swift`: the reusable `LibreCRKit` Swift package.
- `Sources/LibreCRKit`: BLE, NFC activation, pairing, crypto, persistence, and
  data-plane code.
- `Apps/LibreCR`: an iOS PoC app that exercises pairing, state persistence,
  reconnect, backfill, and decoded realtime glucose/status display.
- `protocol.md`: a protocol-level summary of the NFC, BLE, authorization, and
  data-plane behavior currently modeled by the package.

The public app does not ship captured per-sensor state. Local files such as
`Libre3PatchContext.xml` and `Libre3SensorState.json` are ignored.

## Build

```sh
swift test
```

To work on the iOS PoC app, open `Apps/LibreCR/LibreCR.xcodeproj` in Xcode.
The app target uses the package at the repo root as a local Swift package.

## Current Library Boundary

The package currently owns:

- NFC activation payload construction and response parsing.
- Receiver identity generation, display, and recovery parsing
  (`Libre3ReceiverID`).
- BLE scanning, connecting, GATT discovery, notification subscription, writes,
  reads, CoreBluetooth restoration hooks, and iOS connection-event registration
  (`SensorScanner`, `SensorSession`).
- First-pair authorization primitives through Phase 6, including standard
  ECDSA-P256(SHA-256) verification of the sensor certificate with bundled
  Abbott patch-signing public keys.
- Post-auth data-plane framing, CCM decrypt, `patchStatus`, and realtime
  `glucoseData` parsing.
- Lifecycle and backfill helpers: `SensorLifecycle`, raw quality evidence,
  `Libre3GlucoseQualityAssessment`,
  `Libre3DataPlaneState`,
  `PatchControlCommand.backfillGreaterEqual`, `HistoricalReadingPage`,
  `HistoricalBackfill` coverage/gap summaries, clinical-data records, factory
  data command access, and bounded reconnect backfill command planning from the
  last accepted glucose life count.
- Persistence bridges between `Libre3SensorState` and `Libre3DataPlaneState`
  for seeding reconnect backfill after app relaunch.

An integrating app should own:

- User-facing pairing and recovery workflows.
- Persistence in app settings, keychain, cloud/device backup, or other durable
  state chosen by the app.
- Conversion from `RealtimeGlucoseReading` into the app's glucose sample model.
- Connection state policy, retry cadence, and UI error state.
- Background launch orchestration from app lifecycle callbacks.
- Protocol conformance and conversion into the app's own glucose sample types.

## Recovery Metadata

A Libre 3 receiver ID is the 4-byte value placed into the NFC activation/switch
payload as:

```text
timestamp_LE || receiverID_LE || abbott_crc16
```

The sensor-facing value is the receiver ID itself. A LibreView account is not a
protocol requirement for the observed first-pair and active-sensor recovery
paths.

Apps that support sensor recovery should persist and expose at least:

- `receiverID` as 4-byte little-endian hex.
- Sensor serial number.
- BLE address returned by NFC.
- Latest BLE PIN returned by NFC.
- Sensor start / lifecycle metadata once the remaining fields are named.

If a user loses the original phone, a new install can accept the saved
`receiverID` before scanning the active sensor. Active-sensor recovery then uses
the switch-receiver NFC command and the normal BLE authorization flow.

## Data Quality

Each `RealtimeGlucoseReading` carries the sensor's own quality channels (data
quality error, sensor condition, displayable-range status, and actionability).
`currentGlucoseQualityAssessment(lifecycle:)` folds these into a
`Libre3GlucoseQualityAssessment` with an overall `isUsable` flag plus the
contributing `issues`.

Issues are split into two classes:

- Blocking issues suppress the reading: sensor warmup, expiry, a data-quality
  error, an unavailable/out-of-range value, or an abnormal sensor condition.
  These clear `isUsable` and are exposed via `blockingIssues`.
- Advisory issues are surfaced for visibility but do not suppress the reading.
  Currently the only advisory is `notActionable`, exposed via `advisories`.

Actionability (bit 3 of the realtime status byte) is intentionally advisory.
Abbott's own app still displays the glucose value for a non-actionable reading;
the bit only optionally drives a "non-actionable" overlay icon. A reading whose
other quality channels are clean therefore stays usable even when the sensor
reports it as non-actionable. Integrating apps that want stricter behavior can
inspect `reading.actionability` or the `advisories` list directly.

## Standalone POC Exercise App

The `Apps/LibreCR` NFC tab is currently the live-device harness for the public
integration surface. It uses product-facing "pairing" language:

- Initial pairing: a new sensor that accepts activation/switch NFC and BLE
  authorization with the current receiver ID.
- Sensor recovery pairing: a post-A8 active sensor that accepts the known saved
  receiver ID, then completes BLE authorization and resumes realtime data.

The harness now displays decoded `glucoseData` and `patchStatus`, persists
`Libre3SensorState.json`, records the last realtime glucose life count/value for
bounded reconnect backfill, can reconnect from that saved state, exposes an
explicit BLE disconnect button, registers CoreBluetooth connection-event wake
hooks, keeps a model-owned post-auth listener alive after the initial bootstrap,
and records scene/restoration/connection lifecycle events in-app. Temperature is
shown as the currently grounded raw field (`tempRaw`) until its unit/calibration
is confirmed.

## Background Lifecycle Behavior

The four live-device behaviors that the library is shaped around have been
exercised end-to-end in real use:

- Background while connected: minute-spaced `glucoseData` notifications wake
  the app and are decrypted from the locked/backgrounded state.
- iOS termination restoration: `willRestoreState` delivers the peripheral and
  subscribed characteristics after system-driven termination.
- Disconnect recovery: registered connection events wake the app on reconnect
  or service match.
- Long idle run: locked-phone sessions sustain sample continuity against the
  sensor's history/backfill channel.

The library still deliberately exposes low-level hooks rather than owning a
finished CGM lifecycle policy, because the host app's connection-state policy,
retry cadence, persistence, and UI belong in the integrating app.

## Reconnect Authorization Scope

After a sensor is initially paired and saved, an app can skip onboarding, avoid
repeating NFC activation/switch unless the saved state is missing, seed
`Libre3DataPlaneState` from the saved last glucose point, and request bounded
backfill instead of draining all available history.

Pristine post-pairing captures show two reconnect shapes:

- Cached/direct reconnect: `0x11 StartAuthorization`, R1/nonce notify, Phase 5
  write, `0x08 SendChallengeLoadDone`, then `0843` + Phase 6. LibreCRKit exposes
  this as `runCachedReconnectPreamble` and `runCachedReconnectHandshake`.
  Callers that persist the raw kAuth blob can derive the cached Phase 5 raw key
  with `Child23KAuthImport.phase5RawKey(forKAuthBlob:)`.
- Full fallback authorization: certificate exchange, ephemeral exchange,
  `StartAuthorization`, Phase 5, and Phase 6. LibreCRKit exposes this as
  `runCommandGatedAuthorizationPreamble` and
  `runCommandGatedAuthorizationHandshake`. The older first-pair method names
  remain for compatibility.

The cached/direct path is the preferred saved-state reconnect attempt when the
integration has accepted Phase 5 material for that sensor/receiver state. If it
is rejected before Phase 6, fall back to the full authorization path.

## License

LibreCRKit is available under the MIT License. See [LICENSE](LICENSE).
