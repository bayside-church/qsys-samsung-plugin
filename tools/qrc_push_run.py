"""Push a Lua file into a running Control Script over QRC, reload it, and stream its log.

Usage:
  python tools/qrc_push_run.py <script.lua> <seconds> [--set NAME=value ...]
                               [--comp Control_Script_V2] [--host 127.0.0.1]

Requires a design running (Designer emulation or a real Core) containing a
Control Script component whose "Script Access" property is All.

* `--[[ #include "path" ]]` directives are expanded (paths relative to the
  current working directory, i.e. run this from the repo root) so the harness
  can pull in the plugin's real src/ modules exactly as PLUGCC would.
* `--set NAME=value` rewrites the first `NAME = "..."` assignment in the
  expanded script, so IPs and tokens stay out of the repo.
* Streaming stops early when a log line containing "FULL TRANSCRIPT" arrives.

WARNING: the pushed script becomes the Control Script's code and RE-RUNS every
time the design (re)starts — including every File -> Emulate. A pushed power
scenario will fire again then. When done testing, push an idle script:
    printf 'print("idle")
' > idle.lua && python tools/qrc_push_run.py idle.lua 3
"""
import json
import re
import socket
import sys
import time

args = sys.argv[1:]
path, dur = args[0], float(args[1])
sets, comp, host = {}, "Control_Script_V2", "127.0.0.1"
i = 2
while i < len(args):
    if args[i] == "--set":
        k, v = args[i + 1].split("=", 1); sets[k] = v; i += 2
    elif args[i] == "--comp":
        comp = args[i + 1]; i += 2
    elif args[i] == "--host":
        host = args[i + 1]; i += 2
    else:
        raise SystemExit(f"unknown arg {args[i]}")

INCLUDE = re.compile(r'--\[\[\s*#include\s+"([^"]+)"\s*\]\]')

def expand(text, depth=0):
    if depth > 8:
        raise SystemExit("include nesting too deep")
    def sub(m):
        with open(m.group(1), encoding="utf-8") as f:
            return f"-- >>> {m.group(1)}\n" + expand(f.read(), depth + 1) + f"\n-- <<< {m.group(1)}"
    return INCLUDE.sub(sub, text)

with open(path, encoding="utf-8") as f:
    code = expand(f.read())
for k, v in sets.items():
    code, n = re.subn(rf'^(\s*{re.escape(k)}\s*=\s*)"[^"]*"', lambda m: f'{m.group(1)}"{v}"', code, count=1, flags=re.M)
    if not n:
        raise SystemExit(f"--set {k}: no `{k} = \"...\"` line found")

s = socket.create_connection((host, 1710), timeout=5)
buf = b""

def send(m):
    s.sendall((json.dumps(m) + "\0").encode())

def recv_until(id_):
    global buf
    while True:
        chunk = s.recv(65536)
        if not chunk:
            raise SystemExit("QRC closed")
        buf += chunk
        while b"\0" in buf:
            msg, _, buf = buf.partition(b"\0")
            m = json.loads(msg)
            if m.get("id") == id_:
                return m

def setc(id_, name, value):
    send({"jsonrpc": "2.0", "id": id_, "method": "Component.Set",
          "params": {"Name": comp, "Controls": [{"Name": name, "Value": value}]}})
    return recv_until(id_).get("result")

setc(1, "log.clear", 1)
print("set code:", setc(2, "code", code))
print("reload:", setc(3, "reload", 1))
send({"jsonrpc": "2.0", "id": 4, "method": "ChangeGroup.AddComponentControl",
      "params": {"Id": "t", "Component": {"Name": comp, "Controls": [
          {"Name": "log.history"}, {"Name": "script.status"}, {"Name": "script.error.count"}]}}})
send({"jsonrpc": "2.0", "id": 5, "method": "ChangeGroup.AutoPoll", "params": {"Id": "t", "Rate": 0.05}})

last, end = {}, time.time() + dur
s.settimeout(1)
while time.time() < end:
    try:
        chunk = s.recv(65536)
    except socket.timeout:
        continue
    if not chunk:
        break
    buf += chunk
    while b"\0" in buf:
        msg, _, buf = buf.partition(b"\0")
        m = json.loads(msg)
        if m.get("method") == "ChangeGroup.Poll":
            for c in m["params"]["Changes"]:
                if c["String"] != last.get(c["Name"]):
                    last[c["Name"]] = c["String"]
                    print(f'[{c["Name"]}] {c["String"]}', flush=True)
                    if c["Name"] == "log.history" and "FULL TRANSCRIPT" in c["String"]:
                        end = 0
