#!/usr/bin/env python3
"""Spike: can a PermissionRequest hook answer AskUserQuestion for the user?

Runs as a PermissionRequest hook for AskUserQuestion. If spike/answers.json
appears (waiting up to the seconds in spike/ask_hold), the hook allows the
tool with updatedInput = the original questions plus those answers, so the
notch could answer instead of the dialog. answers.json maps question text to
the chosen label (or any free text); the key "*" answers every question.
Without answers.json the hook prints nothing and the normal dialog is shown.
"""
import json
import os
import sys
import time
from datetime import datetime

SPIKE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(SPIKE, "log")
HOLD = os.path.join(SPIKE, "ask_hold")
ANSWERS = os.path.join(SPIKE, "answers.json")
WAITING = os.path.join(SPIKE, "ask_waiting.json")
SKIP = os.path.join(SPIKE, "skip_sessions")


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


def poll_answers(seconds):
    deadline = time.time() + seconds
    while True:
        if os.path.exists(ANSWERS):
            with open(ANSWERS, encoding="utf-8") as f:
                answers = json.load(f)
            os.remove(ANSWERS)
            return answers
        if time.time() >= deadline:
            return None
        time.sleep(0.5)


def build_answers(questions, given):
    answers = {}
    for q in questions:
        text = q.get("question", "")
        if text in given:
            answers[text] = given[text]
        elif "*" in given:
            answers[text] = given["*"]
    return answers


def main():
    data = json.loads(sys.stdin.read())
    if data.get("tool_name") != "AskUserQuestion":
        return
    if data.get("session_id") in skipped_sessions():
        return

    tool_input = data.get("tool_input", {})
    started = time.time()
    hold = read_hold_seconds()
    if hold > 0:
        with open(WAITING, "w", encoding="utf-8") as f:
            json.dump({
                "session_id": data.get("session_id"),
                "since": datetime.now().isoformat(timespec="seconds"),
                "questions": tool_input.get("questions", []),
            }, f, ensure_ascii=False, indent=2)
    try:
        given = poll_answers(hold)
    finally:
        if os.path.exists(WAITING):
            os.remove(WAITING)

    output = None
    if given:
        answers = build_answers(tool_input.get("questions", []), given)
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "allow",
                    "updatedInput": {**tool_input, "answers": answers},
                },
            }
        }

    os.makedirs(LOG, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    with open(os.path.join(LOG, f"ask-{stamp}.json"), "w", encoding="utf-8") as f:
        json.dump({
            "session_id": data.get("session_id"),
            "hold_seconds": hold,
            "waited_seconds": round(time.time() - started, 1),
            "given": given,
            "output": output,
        }, f, ensure_ascii=False, indent=2)

    if output:
        print(json.dumps(output, ensure_ascii=False))


if __name__ == "__main__":
    main()
