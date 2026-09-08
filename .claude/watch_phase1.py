import os, psycopg, time

c = psycopg.connect(os.environ["DATABASE_URL"])
cur = c.cursor()

# WATCH MODE: Pat just triggered a backfill manually, then will cut BT for 10 min.
# Phase 1 NOW: watch this backfill attempt (realtime still on, he's about to cut BT).
# Log what happens so we have a clean baseline.

print("=== PHASE 1: backfill avant coupure BT ===", flush=True)
cur.execute("""
SELECT recv_ts, body FROM app_log
WHERE title='gen4.command.sent' AND recv_ts > now() - interval '2 minutes'
ORDER BY recv_ts DESC LIMIT 8""")
for r in cur.fetchall():
    print(f"  {r[0].strftime('%H:%M:%S')} | {r[1][:90]}", flush=True)

cur.execute("""SELECT count(*) FROM raw_frame
WHERE packet_type=36 AND received_at > now() - interval '2 minutes'
  AND substring(frame_hex from 13 for 2) IN ('16','22')""")
print(f"  échos cmd22/34: {cur.fetchone()[0]}", flush=True)

# Journal lines (the new sync.journal)
cur.execute("""
SELECT recv_ts, body FROM app_log
WHERE title='sync.journal' AND recv_ts > now() - interval '5 minutes'
ORDER BY recv_ts ASC LIMIT 12""")
print("  journal:", flush=True)
for r in cur.fetchall():
    print(f"    {r[0].strftime('%H:%M:%S')} | {r[1][:90]}", flush=True)

c.close()
