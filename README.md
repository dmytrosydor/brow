# brow

Claude sessions in the MacBook notch. brow shows which sessions finished, which are asking something and which are still working. From the notch you can read the last message, reply, press the suggested buttons, pick an answer to a question or run the suggested command in Ghostty. Works with both the Claude desktop app and `claude` in the terminal.

Author: Dmytro Sydor.

## How it works

`brow-hook` is a Claude Code command hook. It forwards each hook event to brow over `~/Library/Application Support/brow/brow.sock`. For `Stop` and `PermissionRequest` (AskUserQuestion) it waits for brow's answer:

- When Claude stops and that session's window is not in front, brow holds the hook. A reply typed in the notch, or a wrap_up button, is returned as `{"decision":"block","reason":…}` and Claude reads it as the next message.
- An AskUserQuestion is answered with `updatedInput.answers`; whichever answers first, the notch or the app, wins.
- A hold ends without a reply when you switch to that app, write there, the session ends, the hold times out (10 min by default) or brow quits.

If brow is not running, `brow-hook` exits at once and prints nothing, so Claude is never held up.

## Build and run

```bash
cd app && scripts/build-app.sh && open build/brow.app
```

Right-click the notch for the menu: hold on/off, how long to wait, launch at login, connect to all Claude sessions (adds the hooks to `~/.claude/settings.json`, keeps a backup), quit. The same from the command line: `brow --install-hooks` / `--uninstall-hooks` (`--yes` skips the dialog, `BROW_CLAUDE_SETTINGS` points at another file).

This repo's `.claude/settings.json` holds only the spike hooks; brow itself is connected through the user settings.

Session ids listed in `~/Library/Application Support/brow/skip_sessions` are never held.

## Develop

```bash
cd app && swift build -c release && .build/release/Brow --open
```

Flags: `--open` starts expanded; `--demo` uses demo data; `--state collapsed|list|question|command|buttons|sent` opens a demo screen. `BROW_DEBUG=1` prints received events to stderr and lets `scripts/brow-ctl.py` reply, answer, release or select a session as if the notch was clicked.

- `spike/` — the hook experiments that proved the idea.
- `docs/PLAN.md` — the plan; `docs/brow.pdf` — overview with screenshots.
