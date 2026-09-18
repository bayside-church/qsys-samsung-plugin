"""Stream a component's log.history over QRC. Usage: python tools/qrc_tail.py <component> <seconds>"""
import json, socket, sys, time
comp, dur = sys.argv[1], float(sys.argv[2])
s = socket.create_connection(("127.0.0.1", 1710), timeout=5)
def send(m): s.sendall((json.dumps(m) + "\0").encode())
send({"jsonrpc":"2.0","id":1,"method":"ChangeGroup.AddComponentControl","params":{"Id":"tail","Component":{"Name":comp,"Controls":[{"Name":"log.history"}]}}})
send({"jsonrpc":"2.0","id":2,"method":"ChangeGroup.AutoPoll","params":{"Id":"tail","Rate":0.05}})
buf=b""; last=None; end=time.time()+dur; s.settimeout(1)
while time.time()<end:
    try: chunk=s.recv(65536)
    except socket.timeout: continue
    if not chunk: break
    buf+=chunk
    while b"\0" in buf:
        msg,_,buf=buf.partition(b"\0"); m=json.loads(msg)
        if m.get("method")=="ChangeGroup.Poll":
            for c in m["params"]["Changes"]:
                if c["String"]!=last:
                    last=c["String"]; print(last, flush=True)
