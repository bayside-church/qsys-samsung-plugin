"""Minimal QRC (JSON-RPC over TCP 1710) client. Usage: python tools/qrc.py '{"method":"StatusGet","params":0}' ..."""
import socket, json, sys
def qrc(*calls, host="127.0.0.1", port=1710, timeout=5):
    s = socket.create_connection((host, port), timeout=timeout)
    buf = b""
    out = []
    for i, c in enumerate(calls):
        c = dict(c); c.setdefault("jsonrpc", "2.0"); c["id"] = i + 1
        s.sendall(json.dumps(c).encode() + b"\0")
        while True:
            chunk = s.recv(65536)
            if not chunk: break
            buf += chunk
            while b"\0" in buf:
                msg, _, buf = buf.partition(b"\0")
                m = json.loads(msg)
                if m.get("id") == i + 1:
                    out.append(m); break
                # engine status / other unsolicited — print for context
                print("<<", json.dumps(m)[:300], file=sys.stderr)
            else:
                continue
            break
    s.close()
    return out
if __name__ == "__main__":
    for r in qrc(*[json.loads(a) for a in sys.argv[1:]]):
        print(json.dumps(r, indent=1))
