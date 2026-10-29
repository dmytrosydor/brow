# Spike: what Claude Code hooks can do

Before brow was built, these probes checked what hooks expose and whether a reply can be handed back to Claude from outside. They are kept as a record; brow does not use them.

- `stop_probe.py` (Stop): logs `last_assistant_message`; when `spike/hold` holds a number of seconds, waits that long for `spike/reply.txt` and returns it as `{"decision": "block", "reason": …}`. Claude continues with the reply.
- `event_log.py`: logs what PreToolUse / PostToolUse / PermissionRequest carry for AskUserQuestion and the desktop app's wrap_up box.
- `ask_probe.py` (PermissionRequest): when `spike/answers.json` appears, answers AskUserQuestion with `updatedInput.answers`. The desktop app still shows its own dialog meanwhile; the first answer wins.

To run them, copy `settings.example.json` to `.claude/settings.json` in this repo and start a Claude session here. Logs go to `spike/log/`. Session ids listed in `spike/skip_sessions` are never held.
