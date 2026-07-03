# 🚦 Claude Traffic Light

A tiny desktop status light for **Claude Code**. See the live state of **all your Claude tabs at a glance** — without alt-tabbing through them.

- 🟢 **Green** — Claude is working
- 🟡 **Yellow** — Claude is waiting for you (a question or a permission)
- 🔴 **Red** — Claude is done

Each light shows a **count badge** (how many sessions are in that state), plays a soft **chime** the moment a new session needs you, a distinct **ding-dong** when a session finishes its work, and floats **always-on-top** over any app — even Unity, games, or your browser.

And it's not just a light:

- **Click a light to jump** — click yellow and the terminal that's waiting for you comes to the front. Multiple sessions? A picker menu appears.
- **Live activity panel** — hover to see every session by name, what tool it's running right now (`Bash`, `Edit`, …) and **for how long** (`my-app - Bash (2m)`).
- **Stuck alert** — if a question has been waiting for 3+ minutes, the yellow light gets a white ring so you can't miss it.

> Runs entirely on your machine. No account, no server, no telemetry. It just reads Claude Code's own hook events.

![demo](docs/demo.gif)

---

## Install

**Windows** (PowerShell):

```powershell
git clone https://github.com/Eneslexi/claude-traffic-light.git
cd claude-traffic-light
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

That's it. The light starts immediately and **auto-launches with every future Claude Code session**. A desktop shortcut (`Claude Traffic Light`) is also created so you can open it manually any time.

> The installer **merges** its hooks into your existing `~/.claude/settings.json` — it never overwrites your other hooks, and re-running is safe.

---

## Controls

| Action | What it does |
|---|---|
| **Click a light** | Jump to that session's window (picker menu if there are several) |
| **Drag** | Move the light anywhere |
| **Scroll** / **Ctrl + drag** | Resize |
| **Hover** | Live panel: every session by name, current tool, and elapsed time |
| **Right-click** | Switch **Vertical / Horizontal**, or **Close** |

Position, size and orientation are remembered between sessions.

---

## How it works

Claude Code fires [hooks](https://docs.claude.com/en/docs/claude-code/hooks) on lifecycle events. The installer wires nine of them to tiny shell scripts that write each session's state to `~/.claude/traffic_lights/<session>.txt`:

| Hook | State |
|---|---|
| `SessionStart` | starts the light + green |
| `UserPromptSubmit`, `PreToolUse` | 🟢 working |
| `Elicitation`, `PermissionRequest` | 🟡 waiting |
| `ElicitationResult`, `PermissionDenied` | 🟢 working |
| `Stop` | 🔴 done |
| `SessionEnd` | removes the session |

Each state file carries four lines: the state, the tab's title, the tool currently running, and when the state began — that's how the panel knows a session has been waiting for 4 minutes on a `Bash` approval.

A small PowerShell/WinForms window watches that folder with a `FileSystemWatcher` (event-driven, near-zero CPU) and lights up the instant anything changes. Files older than 6 hours are ignored, so stale/crashed sessions don't linger. Click-to-jump finds the session's window by matching its tab title and brings it to the front.

---

## 📱 Phone notifications (optional, already built into Claude)

This tool is **desktop-only by design** — and you don't need it for phone alerts. If you use Claude Code's **Remote Control**, Claude already pushes a notification to the Claude mobile app when a session needs you. Nothing to install here for that.

> Tip: mobile push is suppressed while your Claude window has focus (i.e. while you're clearly at your desk). Lock your PC or switch windows and you'll get the ping. That's intentional.

---

## Requirements

- Windows 10/11
- Claude Code (with hooks support)
- `bash` available on PATH (Git Bash — ships with Git for Windows)

---

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes only this tool's hooks (yours stay), deletes its files and the shortcut.

---

## License

MIT — do whatever you want. If you build something cool on top, I'd love to see it.

Made while building in public. 🐺
