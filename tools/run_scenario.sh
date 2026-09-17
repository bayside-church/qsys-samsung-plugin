#!/bin/sh
# Usage: tools/run_scenario.sh <scenario> <seconds> <tv_ip> <rpc_token> [extra --set args]
# Runs the harness against a TV and prints a filtered transcript.
sc=$1; secs=$2; ip=$3; tok=$4; shift 4
python tools/qrc_push_run.py tools/harness_runtime.lua "$secs" --set TV_IP="$ip" --set RPC_TOKEN="$tok" --set SCENARIO="$sc" "$@" > /dev/null 2>&1
python tools/qrc.py '{"method":"Component.Get","params":{"Name":"Control_Script_V2","Controls":[{"Name":"log.history"},{"Name":"script.error.count"}]}}' 2>/dev/null \
  | python -c "import json,sys; d=json.load(sys.stdin); [print(c['Name'],'=>',c['String']) for c in d['result']['Controls']]" \
  | sed "s/${tok:-@@none@@}/…/g"
