# dsh-desktop-control

一个 [DeepSeek Harness](https://github.com/deepseek-ai) 插件：给模型一个原生的 `desktop` 工具，**截屏看屏幕、移动/点击鼠标、输入文字和组合键**。

它把 `gui.ps1` 脚本（截图 + Win32 输入）包进 DSH 插件，模型直接调用工具，不用每次手拼 PowerShell 命令、也不用担心执行策略。

> Windows only。插件包内自带 `assets/gui.ps1`（UTF-8 BOM），不依赖工作区里的脚本。

## 工具动作

| action | 作用 | 主要参数 |
| :-- | :-- | :-- |
| `screenshot` | 截图并返回 PNG 绝对路径，默认叠加**坐标网格 + 光标** | `window` / `region` / `print` / `grid` / `cursor` / `maxWidth` |
| `windows` | 列出可见窗口（HWND、PID、矩形、标题） | `top` |
| `elements` | 枚举窗口的 **UIA 控件**：名称 + 中心坐标，**不用图** | `window` / `filter` / `depth` / `all` |
| `ocr` | **本地 OCR**（Windows 自带，不联网不耗额度）：文字 + 每行框坐标 | `imagePath` / `filter` |
| `click` | 移动并点击；也支持**按控件名点击** | `x` `y` / `uia` `invoke` / `button` `count` |
| `move` | 移动光标 | `x` `y` |
| `drag` | 按住拖拽 | `x` `y` `x2` `y2` |
| `scroll` | 滚轮 | `x` `y` `amount` |
| `type` | 粘贴文本（走剪贴板，Unicode 安全） | `text` |
| `key` | 组合键，如 `ctrl+s`、`alt+f4` | `key` |
| `activate` | 把窗口提到前台 | `window` |
| `pos` | 光标当前位置 | — |
| `wait` | 等待 | `waitMs` |
| `sequence` | **一次调用跑多个动作**（含截图） | `steps` |

**坐标全部是物理像素**，与 `screenshot` 保存的图片像素一一对应。脚本内部已开启 per-monitor DPI aware v2。

## 为什么它更准、更省 token

以前的循环是「整屏截图 → 模型目测像素 → 点 → 再截」。两个坑：大图被缩小后模型估的坐标是错的；每个动作一次工具往返，历史和 output 都要重算。现在：

**精度**

1. **网格刻度**：截图上每 100px 一条蓝线，边缘标 `x=1200`、`y=600`。**标签就是屏幕像素**，读数字直接点，不用估。
2. **光标标记**：默认画红色十字，模型知道鼠标现在在哪。
3. **缩放比显式回传**：长边超过 `maxWidth`（默认 1440）就等比缩小，返回 `scale`，并在工具结果里写明「图上坐标 × 1/scale = 屏幕像素」。
4. **UIA 控件树**：`elements` 直接给出「名称 + 中心坐标」，`click uia:"保存"` 一步到位，压根不碰像素。
5. **本地 OCR**：对自绘界面（CAD、游戏、Qt）给出文字 + 真实框坐标，比看图猜可靠。

**token**

| 手段 | 省在哪 |
| :-- | :-- |
| `sequence` 批量动作 | 3 个动作从 3 次往返 + 3 个进程压成 1 次 |
| `elements` 替代截图 | 几行文本（几百 token）替代一张图（一两千 token） |
| `screenshot` 只截窗口/区域 | 图更小，证据更短 |
| `maxWidth` 缩放 | 像素数下降，图 token 同比下降 |
| `windows top`、`elements filter` | 输出按需裁剪 |
| 截图不再重复回传 path/size | 去掉冗余字段 |

典型循环，从「看图猜」变成「先问控件」：

```text
elements(window) -> click uia:"保存" -> 只在需要确认时 screenshot
```

视觉兜底时才用：

```text
screenshot(window) -> read_image -> 读网格标签取坐标 -> click -> 小区域 screenshot 验证
```

## 安装

客户端（Electron）：**插件 → + 添加插件**，填入 `dsh-desktop-control`，安装后 **立即启用**。

CLI profile：

```powershell
dsh plugin --profile web add dsh-desktop-control
```

**本地开发（改源码立即生效）**：在客户端「插件」页先移除 npm 版，再把本地目录路径填进安装框，例如
`D:\AI\Deepseek\deepseek-ai-learn\modlens vision\plugins\dsh-desktop-control`。这样改完源码只需重载插件。

## 配置

在 profile 的 `cordis.patch.yml` 里：

```yaml
- id: dsh-desktop-control
  name: dsh-desktop-control
  config:
    enabled: true
    powershellPath: powershell.exe   # 不在 PATH 时再改
    timeoutMs: 30000
    screenshotDir: ''                # 空 = $DSH_HOME/desktop-control
    screenshotMaxWidth: 1440         # 截图长边上限，0 = 不缩放
    screenshotGrid: true             # 默认叠坐标网格
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
| `screenshotGrid` | `true` | 截图默认叠加坐标网格 |
| `screenshotCursor` | `true` | 截图默认标出光标 |
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

- **UIA 看不到 Chromium/Electron/Qt 自绘界面的内容**。实测：DSH 客户端（Electron）、Edge（Chromium）、Abaqus（Qt）都只能拿到窗口外壳、标题栏按钮、菜单栏，网页/画布里的控件不在树里。这类界面请用 `screenshot`（读网格标签）或 `ocr`。
- **OCR 对 12px 左右的中文 UI 小字识别率一般**，会错字（如「截面」→「囤截面」）。工具已内置放大 2 倍再识别并去掉汉字间空格，但结果仍要当作线索、不当真理。它对英文和较大字号更准。
- **全屏 OCR 不省 token**：整屏能识别出上百行，反而比一张图更贵。OCR 只对窗口/区域截图才有性价比。
- 截图是静态图，`sequence` 里的鼠标动作不会等界面动画；需要等就插一条 `wait`。
- UAC 安全桌面、登录界面、锁屏无法操作；部分游戏/反作弊/终端会屏蔽模拟输入。
- 仅 Windows（依赖 PowerShell + user32/gdi32 + Windows.Media.Ocr）。

## 自测

```powershell
npm run selftest
```

只测参数构建和校验（不截图、不动鼠标）：截图默认网格/光标/缩放、`elements`、`ocr` 绝对路径、`click uia`、`sequence` 展开、`type --` 保护等。

## License

MIT
