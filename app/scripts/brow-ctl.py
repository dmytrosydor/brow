#!/usr/bin/env python3
"""Send a test command to a running brow (started with BROW_DEBUG=1).

  brow-ctl.py reply <session> <text>
  brow-ctl.py queue <session> <text>
  brow-ctl.py allow <session>
  brow-ctl.py deny <session> [reason]
  brow-ctl.py select <session>
  brow-ctl.py answer <session> '<json {question: label}>'
  brow-ctl.py release <session>
"""
import json
import os
import socket
import sys

PATH = os.path.expanduser("~/Library/Application Support/brow/brow.sock")

cmd, session = sys.argv[1], sys.argv[2]
payload = {"brow": cmd, "session": session}
if cmd in ("reply", "queue", "deny") and len(sys.argv) > 3:
    payload["text"] = sys.argv[3]
elif cmd == "answer":
    payload["answers"] = json.loads(sys.argv[3])

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(PATH)
s.sendall((json.dumps(payload, ensure_ascii=False) + "\n").encode())
s.recv(64)
s.close()
