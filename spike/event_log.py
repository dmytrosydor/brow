#!/usr/bin/env python3
"""Spike: log any hook event's input to spike/log/ and do nothing else.

Used to see what PreToolUse / PostToolUse / PermissionRequest carry for
AskUserQuestion and the desktop app's wrap_up box, so brow can show them.
"""
import json
import os
import sys
from datetime import datetime

SPIKE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(SPIKE, "log")
SKIP = os.path.join(SPIKE, "skip_sessions")


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except ValueError:
        data = {"_unparsed": raw}
    try:
        with open(SKIP) as f:
            if data.get("session_id") in f.read().split():
                return
    except OSError:
        pass

    os.makedirs(LOG, exist_ok=True)
    event = data.get("hook_event_name", "unknown")
    tool = data.get("tool_name", "")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    name = f"{event}-{tool}-{stamp}.json" if tool else f"{event}-{stamp}.json"
    with open(os.path.join(LOG, name), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
