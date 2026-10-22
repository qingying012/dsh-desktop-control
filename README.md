# dsh-desktop-control

A [DeepSeek Harness](https://github.com/deepseek-ai) plugin that gives the model a native
`desktop` tool: **screenshot the Windows screen, move/click the mouse, type text and key combos**.

It wraps the battle-tested `gui.ps1` script (screenshot + Win32 input) as a DSH plugin, so the
model calls a typed tool instead of assembling PowerShell commands every time.

> Windows only. The package ships its own `assets/gui.ps1` (UTF-8 with BOM); it does not depend on
> a workspace script.

## Actions

| action | What it does | Main args |
| :-- | :-- | :-- |
| `screenshot` | Save a PNG and return its absolute path | `window` / `region` / `print` |
| `windows` | List visible windows (HWND, PID, rect, title) | — |
| `click` | Move and click | `x` `y` `button` `count` |
| `move` | Move the cursor | `x` `y` |
| `drag` | Press, move, release | `x` `y` `x2` `y2` |
| `scroll` | Wheel | `x` `y` `amount` |
| `type` | Paste text via the clipboard | `text` |
| `key` | Key combo, e.g. `ctrl+s`, `alt+f4` | `key` |
| `activate` | Bring a window to the front | `window` |
| `pos` | Cursor position | — |
| `wait` | Sleep | `waitMs` |

**All coordinates are physical pixels**, matching the saved screenshot one-to-one (the script
enables per-monitor DPI awareness v2).

Typical loop:

```text
screenshot -> read_image -> click / type -> screenshot again
```

## Install

Client (Electron): **Plugins → + Add plugin**, paste `dsh-desktop-control`, install, then
**Enable now**.

CLI profile:

```powershell
dsh plugin --profile web add dsh-desktop-control
```

## Configure

```yaml
- id: dsh-desktop-control
  name: dsh-desktop-control
  config:
    enabled: true
    powershellPath: powershell.exe
    timeoutMs: 30000
    screenshotDir: ''   # empty = $DSH_HOME/desktop-control
```

| Option | Default | Meaning |
| :-- | :-- | :-- |
| `enabled` | `true` | `false` registers no tool |
| `powershellPath` | `powershell.exe` | PowerShell executable |
| `timeoutMs` | `30000` | Per-call timeout |
| `screenshotDir` | `$DSH_HOME/desktop-control` | Where screenshots are saved |

## Why a plugin instead of the pwsh tool

The DSH pwsh tool runs children at Low integrity, so `SetCursorPos` / `SendInput` are often
refused and the old script needed `danger-full-access` per approval. This plugin spawns
PowerShell from the host process, outside that sandbox, so input usually works without switching
the permission preset.

## Safety

- Full desktop control: it can click anything and type anything, and screenshots enter the
  model context once you open them with `read_image`.
- Do not enable it on an unattended machine.
- UAC secure desktop, the lock screen, and some games/anti-cheat/terminal apps cannot be driven.

## Self-test

```powershell
npm run selftest
```

Pure argument-construction tests: no screenshot, no mouse movement.

## Limitations

- Windows only.
- One action per call; each call spawns PowerShell (~300–600 ms).
- Static screenshots; the cursor marker is not exposed by the tool.

## License

MIT
