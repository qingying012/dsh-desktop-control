# dsh-desktop-control

A [DeepSeek Harness](https://github.com/deepseek-ai) plugin that gives the model a native
`desktop` tool: **screenshot the Windows screen, locate controls by their text, drive the
mouse/keyboard**.

It wraps the battle-tested `gui.ps1` script (screenshot + Win32 input + local OCR + UI
Automation) as a DSH plugin, so the model calls a typed tool instead of assembling PowerShell
commands every time.

> Windows only. The package ships its own `assets/gui.ps1` (UTF-8 with BOM); it does not depend on
> a workspace script.

## Actions

| action | What it does | Main args |
| :-- | :-- | :-- |
| `find` | Local OCR locates on-screen text and returns screen coordinates (optionally clicks). No image. | `text` / `window` / `click` / `threshold` / `screen` |
| `elements` | UIA control list for a window: name + centre point, no image | `window` / `filter` / `depth` / `all` |
| `ocr` | Local OCR of an image: text + per-line boxes | `imagePath` / `filter` |
| `screenshot` | Save a PNG (cursor stamped by default) and return its path | `window` / `region` / `print` / `grid` / `cursor` / `maxWidth` |
| `windows` | List visible windows (HWND, PID, rect, title) | `top` |
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

**All coordinates are physical pixels** (per-monitor DPI awareness v2 is enabled internally).

## Why it is cheap

The real cost is round-trips, not images: every extra tool call replays the whole history. So the
order is "no image first, screenshot last".

1. **`find`** runs the built-in Windows OCR and returns one line of coordinates:

   ```text
   # find "Save" | window 1296x828 at 312,110 | 64 lines | matches=1
   356,358,42,12|1.00|Save
   ```

   Measured **87 characters (~25 tokens)**, versus 4,000–9,500 characters (1,300–3,100 tokens) of
   structured evidence when a vision model reads the same screen. **~97% cheaper, no quota used.**
   `click:true` clicks the hit in the same call.
2. **`elements`** gives native controls as name + centre point, 70–120 tokens.
3. **`screenshot`** is the last resort: prefer one window or a region, cap the size with `maxWidth`.
4. **`sequence`** collapses click/wait/verify chains; measured 3 actions in 1 call / 535 ms instead
   of 3 calls / 1650 ms.

```text
find "Plugins" -> click (or find click:true) -> screenshot only to verify
```

## Accuracy

- `find` coordinates are the OCR box centres, not an eyeballed guess.
- OCR input is upscaled 2x (12px CJK UI text is otherwise unreadable), coordinates divided back.
- Inter-CJK spaces inserted by Windows OCR are stripped.
- Fuzzy matching: exact 1.00, contains 0.92, reverse-contains 0.78, character overlap otherwise;
  tune with `threshold`.
- A miss returns the three closest lines so the model can reword instead of re-reading the screen.
- Screenshots stamp the cursor; `grid:true` overlays labelled coordinate grid lines (the labels
  are screen pixels) but they get read as text by OCR engines, so the grid is **off by default**.

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
    screenshotGrid: false      # grid labels are picked up as text by OCR
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
| `screenshotGrid` | `false` | Stamp the labelled coordinate grid |
| `screenshotCursor` | `true` | Stamp the cursor crosshair |
| `keepShots` | `40` | Prune older screenshots after each shot |
| `elementsMaxRows` | `140` | Truncate `elements` output (`all:true` disables) |

## Why a plugin instead of the pwsh tool

The DSH pwsh tool runs children at Low integrity, so `SetCursorPos` / `SendInput` are often
refused. This plugin spawns PowerShell from the host process, outside that sandbox, so input
usually works without switching the permission preset.

## Safety

- Full desktop control: it can click anything and type anything, and screenshots enter the model
  context once you open them.
- Do not enable it on an unattended machine.
- UAC secure desktop, the lock screen, and some games/anti-cheat/terminal apps cannot be driven.

## Self-test

```powershell
npm run selftest
```

Pure argument-construction tests: no screenshot, no mouse movement.

## Limitations

- **`find` depends on OCR.** Measured: 2–4 character menu items like "Insert" or "Workspace" hit at
  score 1.00; "Slide Show" was misread as "幻灯片囗节" and only matched partially. A miss returns the
  closest lines so the model can reword.
- **Background capture is blank for some apps.** Windows that are not in the foreground are grabbed
  with `PrintWindow`, which returns an empty bitmap for GPU-rendered apps such as PowerPoint; `find`
  then tells you to `activate` first. Foreground windows use real screen pixels.
- **UIA does not expose Chromium/Electron/Qt painted content.** Measured here: the DSH client,
  Edge and Abaqus only yield the window shell, title-bar buttons and menu bar.
- **A missing or minimised `window` raises an error** instead of silently falling back to the full
  screen (which would capture another window and click the wrong place).
- `sequence` does not wait for animations; insert an explicit `wait` step.
- Windows only.

## License

MIT
