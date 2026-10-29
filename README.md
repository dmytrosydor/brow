# brow

**Your Claude Code sessions, in the MacBook notch.**

![brow open in the notch, listing four Claude sessions](docs/img/hero.png)

brow lives in the notch and shows where each Claude Code session stands: which one is still working, which one finished, and which one is waiting for you. Expand it to read the last message and answer right there — type a reply, press one of the buttons Claude suggested, pick an option in a question, or run the command Claude proposed. It works with both the Claude desktop app and `claude` in the terminal.

[Українською](README.uk.md)

## Features

- **Every session at a glance.** The closed notch shows how many sessions are waiting for you; hover to see them all with their project, title, state and last message.
- **Reply from the notch.** What you type reaches Claude as your next message.
- **Buttons and questions.** The buttons at the end of a reply in the desktop app, and multiple-choice questions (one or several, multi-select or your own answer), work from the notch.
- **Run suggested commands.** A shell block in Claude's message gets a button that opens it in a new [Ghostty](https://ghostty.org) window, in the session's folder. Nothing runs until you click.
- **Stays out of the way.** No Dock icon, no CPU when idle, and if brow is not running Claude behaves exactly as before.
- English and Ukrainian, following the system language.

| Question | Buttons | Command |
|---|---|---|
| ![A multiple-choice question](docs/img/en/question.png) | ![Suggested buttons](docs/img/en/buttons.png) | ![A suggested command](docs/img/en/command.png) |

## Requirements

- macOS 14 Sonoma or later. Made for MacBooks with a notch; on other screens brow shows the same pill at the top centre.
- [Claude Code](https://claude.com/claude-code): the desktop app or the CLI.
- To build: Xcode or the Command Line Tools (Swift 5.10+).
- Optional: Ghostty, for running suggested commands.

## Install

```bash
git clone https://github.com/dmytrosydor/brow.git
cd brow/app
scripts/install.sh
```

This builds `brow.app`, copies it to `/Applications` and starts it. Then **right-click the notch → Connect to all Claude sessions…**. brow shows exactly what it will add to `~/.claude/settings.json` and keeps a copy of the old file next to it.

A prebuilt `brow.app` is attached to each [release](https://github.com/dmytrosydor/brow/releases). It is not notarized by Apple, so after unzipping it into `/Applications` run `xattr -dr com.apple.quarantine /Applications/brow.app` once, or macOS will refuse to open it.

## How it works

```
Claude (app or terminal) ──hook──▶ brow-hook ──Unix socket──▶ brow (notch)
          ▲                                                       │
          └──────────── your reply / answer ◀──────────────────────┘
```

brow adds one small command, `brow-hook`, to Claude Code's [hooks](https://docs.claude.com/en/docs/claude-code/hooks) for these events: `SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`, `SessionEnd`, `PreToolUse`/`PostToolUse` (AskUserQuestion and the wrap_up box) and `PermissionRequest` (AskUserQuestion). The hook passes each event to brow over a socket in `~/Library/Application Support/brow/`.

To get a reply back to Claude, brow briefly **holds** the session:

- When Claude stops and that session's window is not in front, the `Stop` hook waits. Your reply is returned as `{"decision": "block", "reason": …}`, which Claude reads as your next message.
- A multiple-choice question is answered through `PermissionRequest` with `updatedInput.answers`. The app shows its own dialog meanwhile; whichever answers first wins.
- A hold ends without a reply as soon as you switch to that app or type there, the session ends, it times out (10 minutes by default) or brow quits.

While a session is held, the Claude desktop app shows it as still running. Switch to the app and it is let go at once.

## Settings

Right-click the notch:

- **Hold sessions for replies from the notch** — turn holding off to use brow only as a status display.
- **Wait for a reply** — 5, 10, 20 or 30 minutes.
- **Open at login.**
- **Connect to / Disconnect from all Claude sessions.**
- **Quit brow.**

To never hold a particular session, put its id on its own line in `~/Library/Application Support/brow/skip_sessions`.

## Privacy and safety

- Everything stays on your Mac. brow makes no network requests.
- The socket is readable only by your user.
- Commands run only when you press the button, in a new terminal window where you can see them.
- `brow-hook` never blocks Claude when brow is not running: it exits immediately and prints nothing.

## Uninstall

Right-click the notch → **Disconnect from all Claude sessions…**, quit brow and delete `/Applications/brow.app`. Or from the terminal:

```bash
/Applications/brow.app/Contents/MacOS/brow --uninstall-hooks
```

## Known limitations

- Not notarized: see the note under Install.
- Typing in the desktop app while brow holds that session has not been tested much; brow lets the session go as soon as the app comes to the front.
- After a reply from the notch, the desktop app may still draw the old buttons under the message.
- Clicking **Open** brings the right app forward, but not the exact session.
- Sessions that were already running when brow started appear after their next event.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The design notes are in [docs/PLAN.md](docs/PLAN.md), and [spike/](spike/) has the experiments that proved the idea.

## License

[MIT](LICENSE) © 2026 Dmytro Sydor
