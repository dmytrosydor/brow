# Contributing

Issues and pull requests are welcome. For a bigger change, open an issue first so we can agree on the approach.

## Layout

- `app/Sources/Brow/` — the notch app (SwiftUI + AppKit panel).
  - `EventServer.swift` — the Unix socket; one connection per hook call.
  - `LiveEvents.swift` — turns hook events into session state and decides what to hold.
  - `Model.swift` — sessions, holds and replies.
  - `NotchView.swift` — the UI; `Strings.swift` — English/Ukrainian texts.
  - `HookInstaller.swift` — edits `~/.claude/settings.json`.
- `app/Sources/brow-hook/` — the hook command.
- `app/Sources/BrowShared/` — socket helpers shared by both.
- `app/scripts/` — build, install, icon and test scripts.

## Build and run

```bash
cd app
swift build -c release
.build/release/Brow --open          # live, starts expanded
.build/release/Brow --demo          # demo data, nothing is sent
.build/release/Brow --state question  # a demo screen: collapsed|peek|list|question|permission|command|buttons|sent
```

Add `-AppleLanguages "(en)"` or `"(uk)"` to pick the language.

## Test without Claude

Start brow with `BROW_DEBUG=1` to log received events and allow `scripts/brow-ctl.py`, which acts as if the notch was clicked. Feed `brow-hook` a hook event by hand (use `printf '%s'`, not `echo`, so `\n` in the JSON stays escaped):

```bash
BROW_DEBUG=1 .build/release/Brow --open &
printf '%s' '{"session_id":"t1","hook_event_name":"Stop","cwd":"/tmp","last_assistant_message":"Done"}' \
  | env -u CLAUDE_CODE_ENTRYPOINT .build/release/brow-hook &   # waits: brow holds it
python3 scripts/brow-ctl.py reply t1 "Now add tests"         # the hook prints the block decision
```

`brow-ctl.py` also takes `answer <session> '<json>'`, `release <session>` and `select <session>`. Inside a Claude session, `CLAUDE_CODE_ENTRYPOINT` is set in the shell, which makes fake events look like they come from the desktop app; unset it as above.

To try a real session end to end, run `claude -p "…"` with brow running.

## Screenshots and docs

- `docs/img/en/` and `docs/img/uk/` are window captures of `--state` screens in each language.
- `docs/img/hero.png` is `docs/hero.html` rendered with headless Chrome:
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=1280,380 --screenshot=docs/img/hero.png "file://$PWD/docs/hero.html"`
- `docs/brow.pdf` (Ukrainian overview) is `docs/brochure.html` printed the same way with `--print-to-pdf`.

## Style

Match the surrounding code. Commits follow [Conventional Commits](https://www.conventionalcommits.org).
