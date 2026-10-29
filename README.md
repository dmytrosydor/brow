# brow

Claude sessions in the MacBook notch. brow shows which sessions finished, which are asking something and which are still working. From the notch you can read the last message, reply, press the suggested buttons, pick an answer to a question or run the suggested command in Ghostty. Works with both the Claude desktop app and `claude` in the terminal.

Author: Dmytro Sydor.

## Status

- `spike/` — hook experiments that proved the idea (Stop, PermissionRequest, wrap_up).
- `app/` — the notch app (SwiftUI, macOS 14+) and `brow-hook`, the Claude Code hook that feeds it. Sessions show up live (M2); replying from the notch is next.
- `docs/PLAN.md` — plan for the first version; `docs/brow.pdf` — overview with screenshots.

## Run

```bash
cd app && swift build -c release && .build/release/Brow
```

brow listens on `~/Library/Application Support/brow/brow.sock`. `brow-hook` reads a hook event on stdin and forwards it there; if brow is not running it exits at once, so Claude is never held up. This repo's `.claude/settings.json` wires it for sessions started in this folder.

Flags: `--open` starts expanded; `--demo` uses demo data; `--state collapsed|list|question|command|buttons|sent` opens a demo screen. `BROW_DEBUG=1` prints received events to stderr.
