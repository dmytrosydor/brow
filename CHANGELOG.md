# Changelog

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
