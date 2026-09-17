"""Send a raw RPC through a running plugin instance's Raw RPC escape hatch and print the reply.
Usage: python tools/qrc_raw.py <component> '<method> [json-params]' [...]"""
import json, socket, sys, time
comp, cmds = sys.argv[1], sys.argv[2:]
s = socket.create_connection(("127.0.0.1", 1710), timeout=5); buf = b""; nid = 0
def call(method, params):
    global buf, nid
    nid += 1
    s.sendall((json.dumps({"jsonrpc": "2.0", "id": nid, "method": method, "params": params}) + "\0").encode())
    while True:
        buf += s.recv(65536)
        while b"\0" in buf:
            msg, _, buf = buf.partition(b"\0"); m = json.loads(msg)
            if m.get("id") == nid: return m
def setc(name, value):
    return call("Component.Set", {"Name": comp, "Controls": [{"Name": name, "Value": value}]})
def getc(name):
    return call("Component.Get", {"Name": comp, "Controls": [{"Name": name}]})["result"]["Controls"][0]["String"]
for c in cmds:
    setc("RawResponse", ""); setc("RawRPC", c); setc("RawRPCSend", 1); setc("RawRPCSend", 0)
    for _ in range(30):
        time.sleep(0.2); r = getc("RawResponse")
        if r: break
    print(f"  {c:44} -> {r[:150] or '(no response)'}")
