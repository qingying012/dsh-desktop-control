# dsh-desktop-control

一个 [DeepSeek Harness](https://github.com/deepseek-ai) 插件：给模型一个原生的 `desktop` 工具，**截屏看屏幕、按文字定位控件、移动/点击鼠标、输入文字和组合键**。

它把 `gui.ps1` 脚本（截图 + Win32 输入 + 本地 OCR + UI Automation）包进 DSH 插件，模型直接调用工具，不用每次手拼 PowerShell 命令。

> Windows only。插件包内自带 `assets/gui.ps1`（UTF-8 BOM），不依赖工作区里的脚本。

## 工具动作

| action | 作用 | 主要参数 |
| :-- | :-- | :-- |
| `find` | **本地 OCR 找屏幕文字，直接返回屏幕坐标**（可顺手点击），不产生图片 | `text` / `window` / `click` / `threshold` / `screen` |
| `elements` | 枚举窗口的 UIA 控件：名称 + 中心坐标，不用图 | `window` / `filter` / `depth` / `all` |
| `ocr` | 本地 OCR 一张图：文字 + 每行框坐标 | `imagePath` / `filter` |
| `screenshot` | 截图并返回 PNG 路径，默认标出光标 | `window` / `region` / `print` / `grid` / `cursor` / `maxWidth` |
| `windows` | 列出可见窗口（HWND、PID、矩形、标题） | `top` |
| `click` | 移动并点击；也支持按控件名点击 | `x` `y` / `uia` `invoke` / `button` `count` |
| `move` | 移动光标 | `x` `y` |
| `drag` | 按住拖拽 | `x` `y` `x2` `y2` |
| `scroll` | 滚轮 | `x` `y` `amount` |
| `type` | 粘贴文本（走剪贴板，Unicode 安全） | `text` |
| `key` | 组合键，如 `ctrl+s`、`alt+f4` | `key` |
| `activate` | 把窗口提到前台 | `window` |
| `pos` | 光标当前位置 | — |
| `wait` | 等待 | `waitMs` |
| `sequence` | 一次调用跑多个动作（含截图） | `steps` |

**坐标全部是物理像素**，脚本内部开启 per-monitor DPI aware v2。

## 为什么它更省 token

真正的开销不是图，是**轮次**：每多一次工具往返，整段历史就要重放一遍。所以顺序是「先用不产生图的动作，再考虑截图」。

1. **`find` 优先**——`find text:"保存"` 用系统自带 OCR 直接在屏幕上找字，返回一行坐标：

   ```text
   # find "保存" | window 1296x828 at 312,110 | 64 lines | matches=1
   356,358,42,12|1.00|保存
   ```

   实测 **87 字符（约 25 token）**，而让视觉模型读同一屏产生的结构化证据是 4,000–9,500 字符（1,300–3,100 token）。**省 97% 以上，且不消耗任何读图额度**。加 `click:true` 就连点击一起完成，一次往返。

2. **`elements` 其次**——原生控件直接给「名称 + 中心坐标」，70–120 token。
3. **截图是最后手段**——必要时只截目标窗口/区域，`maxWidth` 压尺寸。
4. **`sequence` 合并动作**——点击、等待、验证截图一次跑完；实测 3 个动作从 1650ms/3 次往返降到 535ms/1 次。

典型循环：

```text
find "插件" -> 命中就 click（或 find click:true） -> 只在需要视觉确认时 screenshot
```

## 精度设计

- **`find` 的坐标来自 OCR 文字框的真实中心**，不是模型目测，天然对齐。
- **OCR 前自动放大 2 倍**（12px 中文小字放大后可读），坐标再除回来。
- **去掉汉字间空格**（Windows OCR 会插空格），提高匹配率。
- **模糊匹配**：完全相等 1.00、包含 0.92、反向包含 0.78、字符重叠兜底。OCR 错字也能命中，可用 `threshold` 调松紧。
- **未命中时返回最接近的 3 行**，模型换个关键词即可，不必重读整屏。
- **截图默认标光标**；`grid:true` 可叠坐标网格（标签就是屏幕像素），但网格标签会被 OCR 读成文字，**默认关闭**。

## 安装

客户端（Electron）：**插件 → + 添加插件**，填入 `dsh-desktop-control`，安装后 **立即启用**。

CLI profile：

```powershell
dsh plugin --profile web add dsh-desktop-control
```

**本地开发（改源码立即生效）**：在客户端「插件」页先移除 npm 版，再把本地目录路径填进安装框。

## 配置

```yaml
- id: dsh-desktop-control
  name: dsh-desktop-control
  config:
    enabled: true
    powershellPath: powershell.exe   # 不在 PATH 时再改
    timeoutMs: 30000
    screenshotDir: ''                # 空 = $DSH_HOME/desktop-control
    screenshotMaxWidth: 1440         # 截图长边上限，0 = 不缩放
    screenshotGrid: false            # 网格默认关（标签会被 OCR 读成文字）
    screenshotCursor: true           # 默认画光标
    keepShots: 40                    # 只保留最近 N 张截图
    elementsMaxRows: 140             # elements 输出行数上限
```

| 选项 | 默认值 | 说明 |
| :-- | :-- | :-- |
| `enabled` | `true` | 设为 `false` 时不注册工具 |
| `powershellPath` | `powershell.exe` | PowerShell 可执行文件 |
| `timeoutMs` | `30000` | 单次调用超时 |
| `screenshotDir` | `$DSH_HOME/desktop-control` | 截图落盘目录 |
| `screenshotMaxWidth` | `1440` | 截图长边上限，超出等比缩小并回传 `scale` |
| `screenshotGrid` | `false` | 截图是否叠坐标网格（视觉直接看图时才建议开） |
| `screenshotCursor` | `true` | 截图是否标出光标 |
| `keepShots` | `40` | 截图保留数量，超出删最旧 |
| `elementsMaxRows` | `140` | `elements` 输出截断行数（`all:true` 可绕开） |

## 和直接跑 `gui.ps1` 的区别

| | `gui.ps1` + pwsh 工具 | 本插件 |
| :-- | :-- | :-- |
| 调用方式 | 每次拼命令行 | 原生工具调用，参数结构化 |
| 执行策略 | 受 Restricted 影响，要绕 | 插件内部固定 `-ExecutionPolicy Bypass` |
| 沙箱降权 | DSH 的 pwsh 子进程会被降为 Low 完整性，鼠标键盘常被拒 | 插件在宿主进程内 spawn，不经过 pwsh 沙箱 |
| 截图路径 | 自己管理 | 自动落盘到 DSH home 并返回绝对路径 |

> 也就是说：**用插件通常不需要切 `danger-full-access`**，这是它比脚本顺手的地方。

## 已知限制（重要）

- **`find` 依赖 OCR，短词和生僻字会漏检或错字**。实测「插入」「工作区」这类 2–4 字菜单项在放大 2 倍后能精确命中 1.00；「幻灯片放映」被识别成「幻灯片囗节」，只命中「幻灯片」（0.78）。漏检时工具会给出最接近的行，据此换词。
- **后台截图对部分应用是空白**。窗口不在前台时用 `PrintWindow`，PowerPoint 等 GPU 渲染程序会返回空图；此时 `find` 会提示「先 activate」。前台窗口走真实屏幕像素，不受影响。
- **UIA 看不到 Chromium/Electron/Qt 自绘界面的内容**。实测 DSH 客户端（Electron）、Edge（Chromium）、Abaqus（Qt）都只能拿到窗口外壳、标题栏按钮、菜单栏。这类界面的内容请用 `find` 或 `screenshot`。
- **指定 `window` 但找不到、或窗口已最小化时直接报错**，不会静默退回全屏（避免截到别的窗口后点错位置）。
- 截图是静态图，`sequence` 里的鼠标动作不会等界面动画；需要等就插一条 `wait`。
- UAC 安全桌面、登录界面、锁屏无法操作；部分游戏/反作弊/终端会屏蔽模拟输入。
- 仅 Windows（依赖 PowerShell + user32/gdi32 + Windows.Media.Ocr）。

## 自测

```powershell
npm run selftest
```

只测参数构建和校验（不截图、不动鼠标）：截图默认项、`find` 各参数、`elements`、`ocr` 绝对路径、`click uia`、`sequence` 展开、`type --` 保护等。

## License

MIT
