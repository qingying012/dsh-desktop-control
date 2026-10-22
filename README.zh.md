# dsh-desktop-control

一个 [DeepSeek Harness](https://github.com/deepseek-ai) 插件：给模型一个原生的 `desktop` 工具，**截屏看屏幕、移动/点击鼠标、输入文字和组合键**。

它把之前那套 `gui.ps1` 脚本（截图 + 鼠标键盘控制）包进 DSH 插件，模型直接调用工具，不用每次手拼 PowerShell 命令、也不用担心执行策略。

> Windows only。插件包内自带 `assets/gui.ps1`（UTF-8 BOM），不依赖工作区里的脚本。

## 工具动作

| action | 作用 | 主要参数 |
| :-- | :-- | :-- |
| `screenshot` | 截图并返回 PNG 绝对路径 | `window` / `region` / `print` |
| `windows` | 列出可见窗口（HWND、PID、矩形、标题） | — |
| `click` | 移动并点击 | `x` `y` `button` `count` |
| `move` | 移动光标 | `x` `y` |
| `drag` | 按住拖拽 | `x` `y` `x2` `y2` |
| `scroll` | 滚轮 | `x` `y` `amount` |
| `type` | 粘贴文本（走剪贴板，Unicode 安全） | `text` |
| `key` | 组合键，如 `ctrl+s`、`alt+f4` | `key` |
| `activate` | 把窗口提到前台 | `window` |
| `pos` | 光标当前位置 | — |
| `wait` | 等待 | `waitMs` |

**坐标全部是物理像素**，与 `screenshot` 保存的图片像素一一对应。脚本内部已开启 per-monitor DPI aware v2，图上量到多少就传多少。

典型循环：

```text
screenshot → read_image 看图 → click / type → 再 screenshot 确认
```

## 安装

客户端（Electron）：**插件 → + 添加插件**，填入 `dsh-desktop-control`，安装后 **立即启用**。

CLI profile：

```powershell
dsh plugin --profile web add dsh-desktop-control
```

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
```

| 选项 | 默认值 | 说明 |
| :-- | :-- | :-- |
| `enabled` | `true` | 设为 `false` 时不注册工具 |
| `powershellPath` | `powershell.exe` | PowerShell 可执行文件 |
| `timeoutMs` | `30000` | 单次调用超时 |
| `screenshotDir` | `$DSH_HOME/desktop-control` | 截图落盘目录 |

## 和直接跑 `gui.ps1` 的区别

| | `gui.ps1` + pwsh 工具 | 本插件 |
| :-- | :-- | :-- |
| 调用方式 | 每次拼命令行 | 原生工具调用，参数结构化 |
| 执行策略 | 受 Restricted 影响，要绕 | 插件内部固定 `-ExecutionPolicy Bypass` |
| 沙箱降权 | DSH 的 pwsh 子进程会被降为 Low 完整性，鼠标键盘常被拒 | 插件在宿主进程内 spawn，不经过 pwsh 沙箱 |
| 截图路径 | 自己管理 | 自动落盘到 DSH home 并返回绝对路径 |

> 也就是说：**用插件通常不需要切 `danger-full-access`**，这是它比脚本顺手的地方。

## 安全提醒

- 这是完整的桌面控制：能点任何按钮、能敲任何键、能截下屏幕上的任何内容。
- 截图会进入模型上下文（你随后用 `read_image` 读它），涉密画面先关掉再截。
- 工具调用受宿主工具策略约束；但不要在无人值守的机器上启用。
- UAC 安全桌面、登录界面、锁屏无法操作；部分游戏/反作弊/终端会屏蔽模拟输入。

## 自测

```powershell
npm run selftest
```

只测参数构建和校验（不截图、不动鼠标）：

- `screenshot` 生成绝对 `.png` 路径；
- `type` 对以 `-` 开头的文本使用 `--` 保护；
- `click` 缺坐标、未知 action 会报错；
- `scroll` 两种形式、`move`/`drag`/`key`/`activate`/`pos`/`wait` 的 argv 正确。

## 已知限制

- 仅 Windows（依赖 PowerShell + user32/gdi32）。
- 每次调用起一个 PowerShell 进程，约 300–600ms 开销；高频操作建议一次调用串多个动作（当前工具一次只做一个动作）。
- 截图是整屏/窗口/区域的静态图，不包含光标（除非脚本带 `-cursor`，本工具暂未暴露）。

## License

MIT
