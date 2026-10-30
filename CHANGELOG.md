# Changelog

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
