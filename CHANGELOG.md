# Changelog

## 0.2.0 — 2026-10-30

- Live activity: a working session shows its current action and elapsed time. The text can be hidden in the menu.
- Queue: while Claude works, messages typed in the notch wait and go out together at its next stop. They can be edited or cancelled until then.
- Alerts: the notch slides down for four seconds when a session starts waiting, once per request, and sums up when several wait. Hover to open that session. Sound is optional. No alert when the session's app is in front.
- Permissions from the notch: a card shows the whole command or change, with Allow, Deny, or a typed reason for denying. Several requests at once are shown one by one.
- The hooks now also cover every `PreToolUse`, `PostToolUse`, `PostToolUseFailure` and `PermissionRequest`. brow offers to update hooks from an older version.
- A session is marked as working again after each tool call.

## 0.1.1 — 2026-10-30

- A session held for a reply shows an orange "waiting" dot instead of a green one.
- Claude is told that a reply from the notch is the user's message; before, it could read it as output of the hook.
- The "needs your permission to use AskUserQuestion" notice no longer replaces the last message.
- `BROW_DEBUG` logs carry the time and say whether a hold ended with a reply from the notch or without one.

## 0.1.0 — 2026-10-30

First version.

- Notch panel: closed pill with the number of waiting sessions; on hover, the list of sessions with project, title, state and last message.
- Live sessions from Claude Code hooks (desktop app and CLI) through `brow-hook` and a Unix socket.
- Replies from the notch: free text and the desktop app's suggested buttons, through a held `Stop` hook.
- Multiple-choice questions (AskUserQuestion) answered through `PermissionRequest`: several questions, multi-select, own answer.
- Suggested shell commands run in a new Ghostty window.
- Right-click menu: holding on/off, wait time, open at login, connect/disconnect hooks, quit.
- Hook installer for `~/.claude/settings.json` with a backup; offers to update the path when brow.app is moved.
- English and Ukrainian.
