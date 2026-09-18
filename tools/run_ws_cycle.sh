#!/bin/sh
# Full websocket-tier cycle on a 2016-2019 set: infer ON -> Off -> wait for the
# radio to sleep -> On (WoL) -> confirm. Prints each stage's transcript.
# Usage: tools/run_ws_cycle.sh <tv_ip> <ws_token> <mac>
ip=$1; tok=$2; mac=$3
F="--set TV_IP=$ip --set RPC_TOKEN= --set WS_TOKEN=$tok --set FRIENDLY_NAME=Q-SYS --set MAC_ADDRESS=$mac"
transcript() { python tools/qrc.py '{"method":"Component.Get","params":{"Name":"Control_Script_V2","Controls":[{"Name":"log.history"},{"Name":"script.error.count"}]}}' 2>/dev/null | python -c "import json,sys; d=json.load(sys.stdin); [print(c['String'][:6000]) for c in d['result']['Controls']]" | sed -E "s/$tok/…/g" | grep -aE ">>>|inferring|WoL|TX\] WS \{|WS state|\[ERR\]|^  (Status|PowerStateText|LastError)|=====|^[0-9]+$"; }
echo "=== 1. infer ON then OFF ($(date -u +%H:%M:%S))"
python tools/qrc_push_run.py tools/harness_runtime.lua 300 $F --set SCENARIO=poweroff --set CONNECT_WAIT=255 >/dev/null 2>&1; transcript
echo "=== 2. waiting for a real sleep"
python - <<PY
import socket, time
t0=time.time(); misses=0
while time.time()-t0 < 720:
    try: socket.create_connection(("$ip",8002),timeout=3).close(); misses=0
    except Exception: misses+=1
    if misses>=3: break
    time.sleep(20)
print("  dark at +%ds" % int(time.time()-t0) if misses>=3 else "  never went dark")
PY
echo "=== 3. ON ($(date -u +%H:%M:%S))"
python tools/qrc_push_run.py tools/harness_runtime.lua 95 $F --set SCENARIO=poweron --set CONNECT_WAIT=20 >/dev/null 2>&1; transcript
echo "=== 4. reachable?"
python - <<PY
import socket, time
t0=time.time()
for i in range(8):
    try: socket.create_connection(("$ip",8002),timeout=3).close(); print(f"  +{int(time.time()-t0)}s UP"); break
    except Exception: print(f"  +{int(time.time()-t0)}s down", flush=True)
    time.sleep(5)
PY
