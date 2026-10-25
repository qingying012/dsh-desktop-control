# dsh-desktop-control

A [DeepSeek Harness](https://github.com/deepseek-ai) plugin that gives the model a native
`desktop` tool: **screenshot the Windows screen, read UI Automation / OCR, move/click the mouse,
type text and key combos**.

It wraps the battle-tested `gui.ps1` script (screenshot + Win32 input) as a DSH plugin, so the
model calls a typed tool instead of assembling PowerShell commands every time.

> Windows only. The package ships its own `assets/gui.ps1` (UTF-8 with BOM); it does not depend on
> a workspace script.

## Actions

| action | What it does | Main args |
| :-- | :-- | :-- |
| `screenshot` | Save a PNG stamped with a labelled coordinate grid + cursor | `window` / `region` / `print` / `grid` / `cursor` / `maxWidth` |
| `windows` | List visible windows (HWND, PID, rect, title) | `top` |
| `elements` | UIA control list for a window: name + centre point, no image | `window` / `filter` / `depth` / `all` |
| `ocr` | Local Windows OCR: text + per-line boxes (no network, no quota) | `imagePath` / `filter` |
| `click` | Move and click, or click a control by UIA name | `x` `y` / `uia` `invoke` / `button` `count` |
| `move` | Move the cursor | `x` `y` |
| `drag` | Press, move, release | `x` `y` `x2` `y2` |
| `scroll` | Wheel | `x` `y` `amount` |
| `type` | Paste text via the clipboard | `text` |
| `key` | Key combo, e.g. `ctrl+s`, `alt+f4` | `key` |
| `activate` | Bring a window to the front | `window` |
| `pos` | Cursor position | — |
| `wait` | Sleep | `waitMs` |
| `sequence` | Run several actions in one call (including screenshots) | `steps` |

**All coordinates are physical pixels**, matching the saved screenshot one-to-one (the script
enables per-monitor DPI awareness v2).

## Why it is more accurate and cheaper

- **Grid labels on the image** are screen-pixel coordinates: read them instead of eyeballing.
- **Cursor crosshair** is stamped by default, so the model knows where the pointer is.
- **Scaling is explicit**: long edges above `maxWidth` (default 1440) are scaled and the exact
  `scale` is returned in the tool result.
- **`elements` / `click uia:`** hit real controls by name with no pixels at all.
- **`ocr`** gives text + boxes for painted UIs that UIA cannot see.
- **`sequence`** turns N tool round-trips and N PowerShell starts into one.

```text
elements(window) -> click uia:"Save" -> screenshot only to verify
```

## Install

Client (Electron): **Plugins → + Add plugin**, paste `dsh-desktop-control`, install, then
**Enable now**.

CLI profile:

```powershell
dsh plugin --profile web add dsh-desktop-control
```

Local development: remove the npm copy in the plugin page, then install from the directory path
instead; source edits then take effect after reloading the plugin.

## Configure

```yaml
- id: dsh-desktop-control
  name: dsh-desktop-control
  config:
    enabled: true
    powershellPath: powershell.exe
    timeoutMs: 30000
    screenshotDir: ''          # empty = $DSH_HOME/desktop-control
    screenshotMaxWidth: 1440   # 0 disables scaling
    screenshotGrid: true
    screenshotCursor: true
    keepShots: 40
    elementsMaxRows: 140
```

| Option | Default | Meaning |
| :-- | :-- | :-- |
| `enabled` | `true` | `false` registers no tool |
| `powershellPath` | `powershell.exe` | PowerShell executable |
| `timeoutMs` | `30000` | Per-call timeout |
| `screenshotDir` | `$DSH_HOME/desktop-control` | Where screenshots are saved |
| `screenshotMaxWidth` | `1440` | Long-edge cap; the reply states the scale |
| `screenshotGrid` | `true` | Stamp the labelled coordinate grid |
| `screenshotCursor` | `true` | Stamp the cursor crosshair |
| `keepShots` | `40` | Prune older screenshots after each shot |
| `elementsMaxRows` | `140` | Truncate `elements` output (`all:true` disables) |

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

- **UIA does not expose Chromium/Electron/Qt painted content.** Measured here: the DSH client
  (Electron), Edge (Chromium) and Abaqus (Qt) only yield the window shell, title-bar buttons and
  menu bar. Use `screenshot` (grid labels) or `ocr` for those.
- **OCR is weak on ~12px Chinese UI text.** The tool upscales 2x and strips inter-CJK spaces, but
  expect wrong glyphs; treat its output as a hint, not ground truth. English and larger text do
  much better.
- **Full-screen OCR is not a token saver** — it can return a hundred lines. Reserve it for window
  or region shots.
- `sequence` does not wait for animations; insert an explicit `wait` step.
- Windows only.

## License

MIT
