# WHOOP 4.0 (Gen4) support

This document describes the changes that add **WHOOP 4.0 (Gen4)** Bluetooth
support to Goose, plus a set of stability/performance fixes found while testing
against a real WHOOP 4.0 band. Upstream targeted WHOOP 5.0 only.

Protocol details were verified byte-for-byte against the
[openwhoop](https://github.com/bWanShiTong/openwhoop) reference (commit
`55c5c1e`), which the repo already cites in `Rust/core/src/openwhoop_reference.rs`.

## Background

The **inbound** parser was already generation-aware (`Rust/core/src/protocol.rs`):
Gen4 uses a 4-byte frame header + CRC8, Gen5 an 8-byte header + CRC16-Modbus, and
the inner payload is identical across generations. What was missing was the
**outbound** half — the handshake and commands were hardcoded to the Gen5 frame
and gated on the `fd4b0002` command characteristic. So a WHOOP 4.0 would connect
over BLE but never complete the handshake, leaving every screen empty.

Key insight: the payload is generation-independent — only the frame wrapper and a
few command data bytes differ. So the port is mostly: add a Gen4 frame
builder/deframer, make the hello/gating/opcodes generation-aware, and reuse the
existing inbound parser.

## WHOOP 4.0 support

- **Gen4 frame builder + deframer** (`GooseBLEClient+Parsing.swift`):
  `crc8` (poly `0x07`), `buildGen4CommandFrame` (`[0xAA][len_lo][len_hi][crc8(len)]
  + payload + crc32(payload) LE`, no padding), a generation-aware `buildCommandFrame`
  dispatcher, and `gen4Frames`/`gen4Payload` + `strapFrames`/`strapPayload` for the
  inbound command/response state machines (clock/alarm/sensor/historical), which
  previously assumed the 8-byte Gen5 header.
- **Generation detection / gating** (`GooseBLEClient+Commands.swift`):
  `CommandGeneration`, `activeCommandGeneration` (by command-characteristic UUID
  prefix `61080002` vs `fd4b0002`), and `supportsStrapCommands` replacing the four
  `fd4b0002`-only `supportsV5*` gates.
- **Generation-aware hello** (`GooseBLEClient+UserActions.swift`): Gen4 sends
  `GetHelloHarvard` (cmd 35, data `[0x00]`); Gen5 keeps `GetHello` (cmd 145, `[0x01]`).
  Verified: the Gen4 hello frame is `aa0800a823002300ada86a2d`.
- **Realtime heart rate** (`GooseBLEClient.swift`): on Gen4, live HR is delivered
  over the standard BLE Heart Rate service (180D/2A37), so the realtime set sends
  only `TOGGLE_REALTIME_HR` (cmd 3). It deliberately does **not** send
  `SEND_R10_R11_REALTIME` (cmd 63), whose raw K10/K11 motion firehose bloated
  on-device storage to hundreds of MB in minutes and is not needed for HR.
- **Gen4 historical sync** (`GooseBLEClient+HistoricalCommands.swift`): the openwhoop
  Gen4 preamble (`set_time` → `get_name` → `enter_high_freq_sync` → `history_start`,
  with Gen4 `[0x00]` data bytes, skipping `GET_DATA_RANGE`). Gen4 history-start is
  **fire-and-forget** — the band returns no command response, it just begins
  streaming — so the sync waits on the data stream + idle completion instead of a
  response (otherwise it times out with "SEND_HISTORICAL_DATA timed out").

## Fixes (found against a real WHOOP 4.0)

- **`unsupported device_type: GEN4`** — `bridge.rs::parse_device_type` only accepted
  the string `"GEN_4"`, but Swift sends `"GEN4"`, so every proprietary Gen4 frame
  was rejected (1959 failures in one capture). Now `"GEN4"` is accepted, plus the
  three `expected_device_type()` helpers in `capture_correlation.rs`,
  `capture_import.rs`, `fixtures.rs`.
- **FFI panic safety** — the C-FFI dispatch (`goose_bridge_handle_json`) had no
  `catch_unwind` and the release profile used `panic = "abort"`, so any panic
  crashed the whole app (or was UB across `extern "C"`). The dispatch is now wrapped
  in `catch_unwind` and the release profile uses `panic = "unwind"`, turning a panic
  into a structured JSON error.
- **No auto-capture on connect** — connecting auto-started a 12-hour, full-rate
  packet capture that persisted every frame to SQLite (`GooseAppModel+Lifecycle.swift`),
  the dominant source of UI lag and unbounded DB growth. It is now opt-in.
- **Lightweight default export** — the default raw export pulled raw bytes and the
  large `sensor_samples` table fully into memory, causing OOM crashes
  (`MoreDataStore.swift`). Defaults now exclude raw bytes and `sensor_samples`; the
  full export remains available explicitly.
- **Bounded storage** — `DEFAULT_RAW_EVIDENCE_PAYLOAD_RETENTION_LIMIT_BYTES` was
  512 MB and the live write path passed `compact_raw_payloads: false`, so a WHOOP
  history backlog (pulled oldest-first) could grow the DB into the gigabytes. The
  limit is now 24 MB, the live write path compacts, and a single sync is capped at
  `historicalSyncPacketCap` (6000) packets per pass.

## What works / what doesn't on Gen4

- **Works:** discovery, connection, handshake, live HR, resting HR (recovery,
  packet-derived).
- **Not decoded for any generation** (`metric_readiness.rs` / `openwhoop_reference.rs`
  mark these `NotDecoded` or readiness-blocked): respiratory rate, SpO2, skin
  temperature, signal quality, skin contact; HRV is blocked by
  `hrv_rr_interval_scale_unverified`.
- **Full sleep/recovery** need the band's historical health records (HISTORICAL_DATA,
  type 47). In testing those records were dropped during frame reassembly on the
  Gen4 data characteristic (61080005) while console-log/metadata frames came through,
  so this still needs work (ideally with a raw-notification capture to see the bytes).

## Tests

`Rust/core/tests/gen4_outbound_verification.rs` and
`Rust/core/tests/gen4_protocol_tests.rs` (24 tests): Gen4 frame round-trip with CRC
validation, `"GEN4"`/`"GEN_4"` acceptance via the bridge, 4- vs 8-byte header
geometry, packet-type classification (CONSOLE_LOGS/EVENT/METADATA/COMMAND_RESPONSE),
panic-safety on malformed/truncated/garbage input, and structured bridge errors.

Run: `cd Rust/core && cargo test --test gen4_protocol_tests --test gen4_outbound_verification`
