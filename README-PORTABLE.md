# Nyx Pet 便携版使用说明

## 快速开始

1. 解压压缩包到任意目录，例如 `D:\NyxPet-Portable`。
2. 双击 `Nyx Pet.exe` 启动桌宠。
3. 桌宠会悬浮在桌面上。右键可以打开系统菜单，包含置顶、状态面板、退出等操作。

## 窗口交互

- 透明空白区域不会挡住其他窗口，点击空白处会落到后面的应用。
- 按住宠物本体可以拖动桌宠位置。
- 菜单、技能弹窗、输入框、状态面板和可滚动气泡仍然可以正常点击。
- 不要尝试拖动透明空白区域；便携版只支持拖动宠物本体。

## 默认状态

便携包不会预置任何宠物存档、账本或事件记录。

第一次启动时，宠物会从默认初始状态开始：

- 没有历史事件记录。
- 没有账本流水。
- 没有待触发事件。
- 会在 exe 同级自动创建 `data\` 目录，用于保存之后产生的数据。

如果需要恢复默认状态，退出程序后删除解压目录里的 `data\` 文件夹即可。

重要：不要把已经运行过、带有 `data\` 目录的便携版再次打包发给别人。`data\` 里可能包含运行记录、状态、技能输入和账号密码缓存。

## 玩法特点

- 宠物有心情、体重、发量、健康、金钱等状态。
- 每天会进行收支结算，并可能触发生活事件。
- 事件会影响金钱、心情和健康，也会形成故事线。
- 菜单包含技能、事件、故事、互动、设置等功能。
- 互动里可以让宠物工作、吃饭、锻炼、娱乐，不同动作会改变状态。
- 技能可以运行 Python 脚本，并把脚本输出显示在气泡里。

## 自带技能：计算加班时长

便携版自带一个 `计算加班时长` 技能，对应脚本：

```text
skills\overtime_calculator.py
```

这个技能用于查询并计算指定月份的加班时长。

第一次使用时，点击 `技能 -> 计算加班时长`，程序会弹出输入框：

- `EHR 账号`：用户自己输入。
- `EHR 密码`：用户自己输入，输入框会按密码形式显示。
- `统计年份`：例如 `2026`。
- `统计月份`：例如 `6`。

点击运行后，这些输入会保存到便携版数据目录：

```text
data\skill-inputs.json
```

下一次运行同一个技能时：

- 账号、年份、月份会默认带出上次保存的值。
- 密码不会明文显示在输入框里；密码框留空时，会自动沿用上次保存的密码。
- 如果需要换账号、密码、年份或月份，在弹窗里输入新值即可覆盖保存。

也可以退出程序后直接修改：

```text
data\skill-inputs.json
```

例如把 `query_mon` 改成 `7`，下次就会统计 7 月。

注意：为了实现“输入一次后默认保存”，账号和密码会保存在本机解压目录的 `data\skill-inputs.json` 中。不要把这个文件发给别人。

## 技能扩展方式

技能目录在 exe 同级：

```text
skills\
```

新增技能时，把 Python 脚本放进这个目录，例如：

```text
skills\my_skill.py
```

然后修改：

```text
skills\skills.json
```

示例配置：

```json
[
  {
    "id": "my_skill",
    "name": "我的技能",
    "icon": "✨",
    "command": "python",
    "args": ["my_skill.py"],
    "timeoutSeconds": 30,
    "outputLimit": 3000
  }
]
```

如果技能需要运行时输入参数，可以增加 `prompts`：

```json
{
  "id": "example_login_skill",
  "name": "需要登录的技能",
  "icon": "🔐",
  "command": "python",
  "args": ["example.py"],
  "timeoutSeconds": 30,
  "outputLimit": 3000,
  "prompts": [
    {
      "id": "username",
      "label": "账号",
      "arg": "--username",
      "required": true
    },
    {
      "id": "password",
      "label": "密码",
      "arg": "--password",
      "secret": true,
      "required": true
    },
    {
      "id": "query_mon",
      "label": "统计月份",
      "arg": "--query_mon",
      "defaultValue": "6",
      "required": true
    }
  ]
}
```

说明：

- `id` 必须唯一。
- `name` 是菜单里显示的名称。
- `icon` 是菜单图标。
- `command` 在 Windows 下建议写 `python` 或 `py`。
- `args` 的第一个参数是脚本路径，可以写 `my_skill.py` 或 `skills/my_skill.py`。
- `timeoutSeconds` 是脚本最长运行秒数。
- `outputLimit` 是最多显示多少字符。
- `prompts` 会在运行技能前弹出输入框。
- `prompts[].arg` 会和用户输入的值一起追加到脚本参数里，例如 `--username 用户输入`。
- `prompts[].secret` 为 `true` 时使用密码输入框。
- `prompts[].defaultValue` 是首次运行时的默认值。
- 默认会保存用户输入；如果某个参数不想保存，可以设置 `"persist": false`。

修改 `skills.json` 后，程序会尝试自动刷新技能菜单；如果没有立即出现，退出并重新打开 `Nyx Pet.exe` 即可。

## Python 依赖

运行技能脚本需要电脑已经安装 Python。

如果脚本用到第三方库，例如 `requests`，请先安装：

```powershell
py -m pip install requests
```

## 技能脚本注意事项

- 不要在脚本末尾强制 `pause`，否则桌宠后台运行时可能卡住。
- 如果需要在命令行调试时暂停，可以这样写：

```python
import os
import sys

if sys.stdin.isatty():
    os.system("pause")
```

- 脚本输出到标准输出即可，桌宠会把 `print(...)` 内容显示到气泡里。
- 长输出会显示在可滚动气泡中，默认会停留较长时间。

## 数据保存位置

便携版数据保存在 exe 同级的 `data\` 目录：

```text
NyxPet-Portable\
  data\
    pet-state.json
    events.json
    ledger.json
    pet-settings.json
    skill-inputs.json
```

压缩包里默认不包含 `data\`。第一次运行后才会自动创建。

删除 `data\` 可以重置运行数据，让宠物和技能输入都回到默认初始状态。

## 文件结构

```text
NyxPet-Portable\
  Nyx Pet.exe
  resources\
  skills\
    skills.json
    overtime_calculator.py
    test_skill.py
  README-PORTABLE.md
```

通常只需要双击 `Nyx Pet.exe`。扩展技能时只改 `skills\`。

## 重新打包

在项目根目录执行：

```powershell
npm run dist:win
```

脚本会生成：

```text
dist\NyxPet-Portable.zip
```

打包脚本会自动检查压缩包里是否误带 `data\`、`skill-inputs.json`、事件记录或宠物存档。
