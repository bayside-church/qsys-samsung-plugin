"""Push a Lua file into a running Control Script over QRC, reload it, and stream its log.

Usage:  python tools/qrc_push_run.py <script.lua> <tv_ip> <seconds> [component] [host]

Requires a design running (Designer emulation or a real Core) containing a
Control Script component whose property "Script Access" is set to All. The
script's first `TV_IP = "..."` assignment is rewritten to <tv_ip> before pushing.
Streaming stops early when a log line containing "FULL TRANSCRIPT" arrives.
"""
import socket, json, time, sys, re
path, tv_ip, dur = sys.argv[1], sys.argv[2], float(sys.argv[3])
COMP = sys.argv[4] if len(sys.argv) > 4 else "Control_Script_V2"
HOST = sys.argv[5] if len(sys.argv) > 5 else "127.0.0.1"
code = open(path, encoding="utf-8").read()
code = re.sub(r'TV_IP\s*=\s*"[^"]*"', f'TV_IP    = "{tv_ip}"', code, count=1)
s = socket.create_connection((HOST, 1710), timeout=5)
def send(m): s.sendall((json.dumps(m)+"\0").encode())
buf=b""
def recv_until(id_):
    global buf
    while True:
        chunk=s.recv(65536); buf+=chunk
        while b"\0" in buf:
            msg,_,buf=buf.partition(b"\0"); m=json.loads(msg)
            if m.get("id")==id_: return m
send({"jsonrpc":"2.0","id":1,"method":"Component.Set","params":{"Name":COMP,"Controls":[{"Name":"log.clear","Value":1}]}}); recv_until(1)
send({"jsonrpc":"2.0","id":2,"method":"Component.Set","params":{"Name":COMP,"Controls":[{"Name":"code","Value":code}]}}); print("set code:", recv_until(2).get("result"))
send({"jsonrpc":"2.0","id":3,"method":"Component.Set","params":{"Name":COMP,"Controls":[{"Name":"reload","Value":1}]}}); print("reload:", recv_until(3).get("result"))
send({"jsonrpc":"2.0","id":4,"method":"ChangeGroup.AddComponentControl","params":{"Id":"t","Component":{"Name":COMP,"Controls":[{"Name":"log.history"},{"Name":"script.status"},{"Name":"script.error.count"}]}}})
send({"jsonrpc":"2.0","id":5,"method":"ChangeGroup.AutoPoll","params":{"Id":"t","Rate":0.05}})
last={}; end=time.time()+dur; s.settimeout(1)
while time.time()<end:
    try: chunk=s.recv(65536)
    except socket.timeout: continue
    if not chunk: break
    buf+=chunk
    while b"\0" in buf:
        msg,_,buf=buf.partition(b"\0"); m=json.loads(msg)
        if m.get("method")=="ChangeGroup.Poll":
            for c in m["params"]["Changes"]:
                if c["String"]!=last.get(c["Name"]):
                    last[c["Name"]]=c["String"]
                    print(f'[{c["Name"]}] {c["String"]}', flush=True)
                    if c["Name"]=="log.history" and "FULL TRANSCRIPT" in c["String"]: end=0
