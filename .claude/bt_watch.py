import os, psycopg, time
from datetime import datetime, timezone

CUT_AT = "18:5"  # approx — we detect the actual silence start from the DB

c = psycopg.connect(os.environ["DATABASE_URL"])
cur = c.cursor()

# Find when data stopped (the BT cut): last raw_frame before a silence
cur.execute("""
SELECT max(received_at) FROM raw_frame
WHERE received_at < (SELECT min(received_at) FROM raw_frame WHERE received_at > now() - interval '2 minutes')
""")
row = cur.fetchone()
print("checking silence…", flush=True)

# Simpler: watch live. Poll every 5s. Phase A = silence (BT cut). When frames
# come back, Phase B = countdown from reconnect. Report type-47/cmd22 the
# whole time. Total watch: up to 8 minutes.
start = time.time()
phase = "WAITING_FOR_SILENCE"
silence_since = None

while time.time() - start < 480:
    cur.execute("""SELECT count(*), max(received_at) FROM raw_frame
    WHERE received_at > now() - interval '10 seconds'""")
    n, last = cur.fetchone()
    now_s = time.strftime('%H:%M:%S')

    if phase == "WAITING_FOR_SILENCE":
        if n == 0:
            if silence_since is None:
                silence_since = time.time()
                phase = "SILENCE (band buffering)"
            elapsed_off = time.time() - silence_since
            print(f"[{now_s}] OFF {int(elapsed_off)}s — band buffering…", flush=True)
            if elapsed_off >= 300:  # 5 min reached
                print(f"\n*** 5 MIN ATTEINTES — RALLUME LE BLUETOOTH MAINTENANT ***\n", flush=True)
                phase = "WAITING_FOR_RECONNECT"
        else:
            silence_since = None
            print(f"[{now_s}] data flowing ({n} frames/10s) — waiting for your BT cut…", flush=True)
    elif phase == "SILENCE (band buffering)":
        elapsed_off = time.time() - silence_since
        if n > 0:
            print(f"\n*** DATA BACK after {int(elapsed_off)}s OFF — RECONNECTED! ***", flush=True)
            phase = "RECONNECTED — watching for cmd22 echo + type-47"
        else:
            print(f"[{now_s}] OFF {int(elapsed_off)}s…", flush=True)
    elif phase == "RECONNECTED — watching for cmd22 echo + type-47":
        cur.execute("""SELECT count(*) FROM raw_frame
        WHERE packet_type=36 AND received_at > now() - interval '20 seconds'
          AND substring(frame_hex from 13 for 2) IN ('16','22')""")
        echo = cur.fetchone()[0]
        cur.execute("""SELECT count(*) FROM raw_frame
        WHERE packet_type=47 AND received_at > now() - interval '20 seconds'""")
        t47 = cur.fetchone()[0]
        print(f"[{now_s}] cmd22echo={echo} type47={t47}", flush=True)
        if t47 > 0 or echo > 0:
            print("\n*** BACKFILL SIGNAL! ***", flush=True)
            cur.execute("""SELECT received_at, frame_hex FROM raw_frame
            WHERE (packet_type=47) OR (packet_type=36 AND substring(frame_hex from 13 for 2) IN ('16','22'))
            ORDER BY received_at DESC LIMIT 5""")
            for r in cur.fetchall():
                print(f"   {r[0].strftime('%H:%M:%S')} | {r[1][:80]}", flush=True)
            break
        if time.time() - start > 460:
            print("\n(no type-47/cmd22 within watch window)", flush=True)
            break
    time.sleep(5)

c.close()
