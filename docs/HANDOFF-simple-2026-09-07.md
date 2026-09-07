# Handoff — goose branch `simple`, 2026-09-07 (Pat's Mac session)

## State
- HEAD `simple` = **4ce10c7** (pushed to origin). Builds clean against
  GooseSwift.xcodeproj, DEVELOPMENT_TEAM=2BM23CV57L passed on the CLI
  (target-level team setting is NOT in the pbxproj).
- Installed & running on Pat's iPhone (iPhone 17 Pro Max, id
  C0025A73-012B-5506-A12C-594BA716A318) via xcodebuild + devicectl.
- Token lives in gitignored `GooseSwift/GooseSecrets.xcconfig` — do not commit.

## What 4ce10c7 contains
1. Build fixes: the branch never compiled (merge leftovers): removed orphan
   HomeSleepSection/HomeSkinTempSection, fixed SimpleAppView self?.lastSync,
   gave SleepV2ScheduleTimeline/ClockDial their own optional `lastSleep`,
   restored SyncSection.swift into the Sources build phase (lost in 4b49cc2).
2. GEN4 routing: beginHistoricalSync is V5-only (fd4b0002) and rejected the
   4.0's 61080002 characteristic. Button "Synchroniser maintenant" + 12h
   auto-sync now route to the GEN4 engine when isGen4Band
   (beginGen4HistoricalBackfill / requestGen4HistoricalBackfillIfNeeded(force:)).
   New published state isGen4Backfilling / gen4BackfillPacketCount /
   gen4BackfillStatus / lastGen4BackfillCompletedAt; SyncSection renders the
   GEN4 state (no more permanent "jamais synchronisé" on a 4.0).

## OPEN BUG — GEN4 history pull delivers nothing (verified on VPS)
- Live stream is fine: ~9k hr_sample rows / 12 h, type-43/40 frames flowing.
- gen4.history.request fires (26× in 3 h) but ZERO type-47 HISTORICAL_DATA
  frames arrive (last ever: 2026-07-23). Also no gen4.command.sent log lines
  for cmd=34/22/23 in app_log — the writes in requestGen4HistoricalBackfillIfNeeded
  (GooseBLEClient+Commands.swift) are not going out or not being logged.
- Suspects: the DispatchQueue.asyncAfter(0.6) second write, writeType(for:) on
  61080002 (WriteWithoutResponse vs WithResponse), or the frame format of
  GET_DATA_RANGE(34) with empty payload on this firmware.
- Next step: log writeGen4Command result / peripheral central
  didWriteValueFor errors, and capture what the band answers after cmd=34.

## VPS quick-check snippet
docker exec whoop-api python3 (psycopg3, DATABASE_URL env):
  app_log(recv_ts,title,body) — gen4.* titles;
  raw_frame(packet_type=47) — should grow when backfill works;
  hr_sample(device_ts bigint, wall_ts, bpm) — device_ts epoch is
  2025-09-03 18:22:55 UTC (band boot), not unix.

## Notes
- Pat must accept notifications on first launch (low-battery alert, ≤20%).
- The macOS capture tooling (collector/, python) is the alternate path, not
  needed for the iOS work.
