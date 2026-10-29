# brow

Claude sessions in the MacBook notch. brow shows which sessions finished, which are asking something and which are still working. From the notch you can read the last message, reply, press the suggested buttons, pick an answer to a question or run the suggested command in Ghostty. Works with both the Claude desktop app and `claude` in the terminal.

Author: Dmytro Sydor.

## Status

- `spike/` — hook experiments that proved the idea (Stop, PermissionRequest, wrap_up).
- `app/` — UI prototype on demo data (SwiftUI, macOS 14+).
- `docs/PLAN.md` — plan for the first version; `docs/brow.pdf` — overview with screenshots.

## Run the prototype

```bash
cd app && swift run Brow
```

Hover the notch to expand it. `--state collapsed|list|question|command|buttons|sent` opens a given screen.
