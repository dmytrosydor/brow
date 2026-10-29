#!/usr/bin/env python3
"""Spike: what does a Stop hook see, and can it hand a reply back to Claude?

Runs as a Claude Code Stop hook. For every stop it:
  1. saves the hook input and the last assistant text to spike/log/;
  2. if spike/hold exists (contains N seconds), waits up to N seconds for
     spike/reply.txt; when a reply shows up it is consumed and returned as
     {"decision": "block", "reason": <reply>} so Claude keeps going with it.
Without spike/hold it only checks for an already-written reply.
"""
import json
import os
import sys
import time
from datetime import datetime

SPIKE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(SPIKE, "log")
HOLD = os.path.join(SPIKE, "hold")
REPLY = os.path.join(SPIKE, "reply.txt")
WAITING = os.path.join(SPIKE, "waiting.json")
# Session ids (one per line) the hook must never hold, e.g. the session building brow.
SKIP = os.path.join(SPIKE, "skip_sessions")
SAFE_ENV = (
    "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_DESKTOP_APP_VERSION",
    "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_HOST_SESSION_ID",
    "CLAUDE_PROJECT_DIR",
)


def last_assistant_text(transcript_path):
    if not transcript_path or not os.path.exists(transcript_path):
        return None
    with open(transcript_path, encoding="utf-8") as f:
        lines = f.readlines()
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        if texts:
            return "\n".join(texts)
    return None


def read_hold_seconds():
    try:
        with open(HOLD) as f:
            return int(f.read().strip() or 0)
    except (OSError, ValueError):
        return 0


def skipped_sessions():
    try:
        with open(SKIP) as f:
            return set(f.read().split())
    except OSError:
        return set()


def wait_for_reply(seconds, data):
    if seconds > 0:
        with open(WAITING, "w", encoding="utf-8") as f:
            json.dump({
                "session_id": data.get("session_id"),
                "since": datetime.now().isoformat(timespec="seconds"),
                "last_assistant_message": data.get("last_assistant_message"),
            }, f, ensure_ascii=False, indent=2)
    try:
        return poll_reply(seconds)
    finally:
        if os.path.exists(WAITING):
            os.remove(WAITING)


def poll_reply(seconds):
    deadline = time.time() + seconds
    while True:
        if os.path.exists(REPLY):
            with open(REPLY, encoding="utf-8") as f:
                text = f.read().strip()
            os.remove(REPLY)
            return text or None
        if time.time() >= deadline:
            return None
        time.sleep(0.5)


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except ValueError:
        data = {"_unparsed": raw}

    if data.get("session_id") in skipped_sessions():
        return

    started = time.time()
    hold = read_hold_seconds()
    reply = wait_for_reply(hold, data)

    os.makedirs(LOG, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    record = {
        "input": data,
        # Only non-secret ids: the hook env also carries tokens.
        "env": {k: os.environ.get(k) for k in SAFE_ENV},
        "last_assistant_text": last_assistant_text(data.get("transcript_path")),
        "hold_seconds": hold,
        "waited_seconds": round(time.time() - started, 1),
        "reply": reply,
    }
    with open(os.path.join(LOG, f"stop-{stamp}.json"), "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)

    if reply:
        print(json.dumps({"decision": "block", "reason": reply}, ensure_ascii=False))


if __name__ == "__main__":
    main()
